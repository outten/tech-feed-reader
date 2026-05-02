require_relative 'tags_store'
require_relative 'database'

# Pure rule-matcher. Decides which tags apply to a given article based
# on the rule shape stored in the `tags` table:
#
#   match_kind = 'regex'    → match_value is a Ruby regex source; tested
#                              case-insensitively against title + content_text
#   match_kind = 'keyword'  → match_value is a substring; case-insensitive
#                              substring match against title + content_text
#   match_kind = 'feed_id'  → match_value is the feed id (as a string);
#                              article['feed_id'] must equal it
#
# The applier intentionally takes plain hashes and an array of rules so
# it can be unit-tested without the DB. ArticlesStore.import calls
# .matching_tag_ids per inserted article during bulk import; the /tags
# admin can call .apply_to_existing(tag_id) to backfill new rules
# against the existing article corpus.
module TagsApplier
  module_function

  # `article` is a hash with 'title' / 'content_text' / 'feed_id' keys.
  # `rules` is an array of tag rows from TagsStore.all.
  # Returns the array of tag ids that match.
  def matching_tag_ids(article, rules)
    rules.select { |rule| matches?(article, rule) }.map { |r| r['id'] }
  end

  def matches?(article, rule)
    case rule['match_kind']
    when 'regex'
      regex = Regexp.new(rule['match_value'].to_s, Regexp::IGNORECASE)
      regex.match?(article['title'].to_s) ||
        regex.match?(article['content_text'].to_s)
    when 'keyword'
      kw = rule['match_value'].to_s.downcase
      return false if kw.empty?
      article['title'].to_s.downcase.include?(kw) ||
        article['content_text'].to_s.downcase.include?(kw)
    when 'feed_id'
      article['feed_id'].to_i == rule['match_value'].to_i
    else
      false
    end
  rescue RegexpError
    # Bogus user-supplied regex — log nothing, just skip. Validation
    # happens in the /tags route handler before INSERT.
    false
  end

  # Backfill: scan every article against `tag_id`'s rule and insert
  # article_tags rows for matches. Returns the count of newly tagged
  # articles. Idempotent — INSERT OR IGNORE handles re-runs cleanly.
  def apply_to_existing(tag_id)
    rule = TagsStore.find(tag_id)
    return 0 unless rule

    tagged = 0
    db = Database.connection
    db.transaction do
      db.execute('SELECT id, title, content_text, feed_id FROM articles').each do |article|
        next unless matches?(article, rule)
        if TagsStore.tag_article(article['id'], tag_id)
          tagged += 1
        end
      end
    end
    tagged
  end
end
