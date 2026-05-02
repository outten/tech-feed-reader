require_relative 'database'

# Wrapper around the `tags` and `article_tags` tables. Tags carry a
# match rule (regex / keyword / feed_id) plus a value; the
# applier (TagsApplier) is what actually decides whether an article
# matches. Manual overrides live in the same article_tags table —
# the data layer doesn't distinguish auto-applied from user-applied.
module TagsStore
  KINDS = %w[regex keyword feed_id].freeze

  module_function

  def all
    db.execute('SELECT * FROM tags ORDER BY name ASC')
  end

  def find(id)
    db.execute('SELECT * FROM tags WHERE id = ?', [id]).first
  end

  def find_by_name(name)
    db.execute('SELECT * FROM tags WHERE name = ?', [name]).first
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM tags').first['c']
  end

  # Add a new tag rule. Raises SQLite3::ConstraintException on a
  # duplicate name OR on an unsupported match_kind (the schema's CHECK
  # enforces 'regex' | 'keyword' | 'feed_id').
  def add(name:, match_kind:, match_value:)
    db.execute(<<~SQL, [name, match_kind, match_value])
      INSERT INTO tags(name, match_kind, match_value) VALUES (?, ?, ?)
    SQL
    find(db.last_insert_row_id)
  end

  def remove(id)
    db.execute('DELETE FROM tags WHERE id = ?', [id])
    db.changes.positive?
  end

  # ---- article_tags join helpers --------------------------------------

  def tag_article(article_id, tag_id)
    db.execute(<<~SQL, [article_id, tag_id])
      INSERT OR IGNORE INTO article_tags(article_id, tag_id) VALUES (?, ?)
    SQL
    db.changes.positive?
  end

  def untag_article(article_id, tag_id)
    db.execute('DELETE FROM article_tags WHERE article_id = ? AND tag_id = ?', [article_id, tag_id])
    db.changes.positive?
  end

  def tags_for_article(article_id)
    db.execute(<<~SQL, [article_id])
      SELECT t.*
      FROM tags t
      JOIN article_tags at ON at.tag_id = t.id
      WHERE at.article_id = ?
      ORDER BY t.name
    SQL
  end

  # Return { article_id => [tag_row, ...] } for a list of article ids.
  # Used by listing pages so we don't N+1 per row.
  def tags_for_articles(article_ids)
    return {} if article_ids.empty?
    placeholders = (['?'] * article_ids.length).join(',')
    rows = db.execute(<<~SQL, article_ids)
      SELECT at.article_id, t.id, t.name, t.match_kind, t.match_value
      FROM article_tags at
      JOIN tags t ON at.tag_id = t.id
      WHERE at.article_id IN (#{placeholders})
      ORDER BY t.name
    SQL
    rows.group_by { |r| r['article_id'] }
  end

  # Count of articles per tag — used by /tags + tag chips for context.
  def article_counts
    db.execute(<<~SQL).each_with_object({}) { |r, h| h[r['tag_id']] = r['c'] }
      SELECT tag_id, COUNT(*) AS c FROM article_tags GROUP BY tag_id
    SQL
  end

  class << self
    private

    def db
      Database.connection
    end
  end
end
