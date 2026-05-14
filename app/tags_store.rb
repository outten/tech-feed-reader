require_relative 'database'

# Per-user wrapper around tags + article_tags. Tags carry a match rule
# (regex / keyword / feed_id) and a value; TagsApplier decides whether
# an article matches. Manual overrides live in the same article_tags
# table — the data layer doesn't distinguish auto-applied from
# user-applied.
#
# article_tags doesn't carry its own user_id; instead it inherits scope
# via tags.user_id (the tag's owner is the row's owner). Every query
# that crosses article_tags filters by t.user_id.
module TagsStore
  KINDS = %w[regex keyword feed_id].freeze

  module_function

  def all(user_id = 1)
    db.execute('SELECT * FROM tags WHERE user_id = ? ORDER BY name ASC', [user_id.to_i])
  end

  def find(*args)
    user_id, id = args.length == 2 ? args : [1, args.first]
    db.execute('SELECT * FROM tags WHERE user_id = ? AND id = ?', [user_id.to_i, id]).first
  end

  def find_by_name(*args)
    user_id, name = args.length == 2 ? args : [1, args.first]
    db.execute('SELECT * FROM tags WHERE user_id = ? AND name = ?', [user_id.to_i, name]).first
  end

  def count(user_id = 1)
    db.execute('SELECT COUNT(*) AS c FROM tags WHERE user_id = ?', [user_id.to_i]).first['c']
  end

  # Raises SQLite3::ConstraintException on a duplicate (user_id, name)
  # OR on an unsupported match_kind (the schema CHECK enforces
  # 'regex' | 'keyword' | 'feed_id').
  def add(user_id: 1, name:, match_kind:, match_value:)
    db.execute(<<~SQL, [user_id.to_i, name, match_kind, match_value])
      INSERT INTO tags(user_id, name, match_kind, match_value) VALUES (?, ?, ?, ?)
    SQL
    find(user_id, db.last_insert_row_id)
  end

  def remove(*args)
    user_id, id = args.length == 2 ? args : [1, args.first]
    db.execute('DELETE FROM tags WHERE user_id = ? AND id = ?', [user_id.to_i, id])
    db.changes.positive?
  end

  # ---- article_tags join helpers --------------------------------------
  # The bridge has no own user_id — it inherits from tags.user_id via
  # tag_id. Routes that manually tag are expected to verify ownership
  # via #find(user_id, tag_id) first.

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

  # Cross-user snapshot for the import path. ArticlesStore.import applies
  # every user's tag rules to every new article in one pass; tag_id alone
  # binds the resulting bridge row to its owning user via tags.user_id.
  def all_across_users
    db.execute('SELECT * FROM tags')
  end

  def tags_for_article(*args)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
    db.execute(<<~SQL, [user_id.to_i, article_id])
      SELECT t.*
      FROM tags t
      JOIN article_tags at ON at.tag_id = t.id
      WHERE t.user_id = ? AND at.article_id = ?
      ORDER BY t.name
    SQL
  end

  # { article_id => [tag_row, ...] } scoped to the current user's tags.
  def tags_for_articles(*args)
    user_id, article_ids = args.length == 2 ? args : [1, args.first]
    return {} if article_ids.empty?
    placeholders = (['?'] * article_ids.length).join(',')
    rows = db.execute(<<~SQL, [user_id.to_i] + article_ids)
      SELECT at.article_id, t.id, t.name, t.match_kind, t.match_value
      FROM article_tags at
      JOIN tags t ON at.tag_id = t.id
      WHERE t.user_id = ? AND at.article_id IN (#{placeholders})
      ORDER BY t.name
    SQL
    rows.group_by { |r| r['article_id'] }
  end

  def article_counts(user_id = 1)
    db.execute(<<~SQL, [user_id.to_i]).each_with_object({}) { |r, h| h[r['tag_id']] = r['c'] }
      SELECT at.tag_id, COUNT(*) AS c
      FROM article_tags at
      JOIN tags t ON t.id = at.tag_id
      WHERE t.user_id = ?
      GROUP BY at.tag_id
    SQL
  end

  def top_in_window(user_id = 1, days: 7, limit: 10)
    cutoff = (Date.today - days + 1).to_s
    db.execute(<<~SQL, [user_id.to_i, cutoff, limit])
      SELECT t.id, t.name, COUNT(*) AS count
      FROM tags t
      JOIN article_tags at ON at.tag_id = t.id
      JOIN articles a      ON a.id      = at.article_id
      WHERE t.user_id = ? AND DATE(a.published_at) >= ?
      GROUP BY t.id
      ORDER BY count DESC, t.name ASC
      LIMIT ?
    SQL
  end

  class << self
    private

    def db
      Database.connection
    end
  end
end
