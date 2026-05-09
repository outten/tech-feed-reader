require_relative 'database'
require 'sqlite3'

# Cache of "articles mentioning <player or team>", populated via
# FTS5 phrase search on the entity's full name.
#
# Why caching: the player / team detail page calls refresh_for on
# every visit, but skips the FTS5 + upsert work if the entity's
# articles_indexed_at is fresh (default TTL 1h). Subsequent reads
# hit `for_entity` which is a single index lookup.
#
# kind ∈ 'player' | 'team' (mirrors sports_follows.kind for player + team).
module SportsEntityArticlesStore
  KINDS = %w[player team].freeze
  DEFAULT_TTL_SECONDS = 3600
  DEFAULT_LIMIT       = 30

  module_function

  def db
    Database.connection
  end

  def for_entity(kind:, entity_id:, limit: DEFAULT_LIMIT)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)

    db.execute(<<~SQL, [kind.to_s, entity_id, limit])
      SELECT a.*, sea.matched_at
      FROM sports_entity_articles sea
      JOIN articles a ON a.id = sea.article_id
      WHERE sea.kind = ? AND sea.entity_id = ?
      ORDER BY a.published_at DESC
      LIMIT ?
    SQL
  end

  # Re-runs FTS5 phrase MATCH on `name` and upserts hits for the
  # entity. Skips work when the entity's articles_indexed_at is
  # within TTL — pass force: true to override.
  #
  # Returns a Hash: { skipped: true } when the cache was fresh,
  # otherwise { inserted: <int>, total: <int> }.
  def refresh_for(kind:, entity_id:, name:, ttl: DEFAULT_TTL_SECONDS, force: false, now: Time.now)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)
    name = name.to_s.strip
    return { skipped: true, reason: :empty_name } if name.empty?

    return { skipped: true, reason: :fresh } if !force && fresh?(kind: kind, entity_id: entity_id, ttl: ttl, now: now)

    hits = fts_search(name)
    inserted = 0
    db.transaction do
      hits.each do |article_id|
        db.execute(
          'INSERT OR IGNORE INTO sports_entity_articles(kind, entity_id, article_id) VALUES (?, ?, ?)',
          [kind.to_s, entity_id, article_id]
        )
        inserted += 1 if db.changes.positive?
      end
      stamp_indexed!(kind: kind, entity_id: entity_id, now: now)
    end

    { inserted: inserted, total: hits.length }
  end

  def fresh?(kind:, entity_id:, ttl: DEFAULT_TTL_SECONDS, now: Time.now)
    table = kind_table(kind)
    row   = db.execute("SELECT articles_indexed_at FROM #{table} WHERE id = ?", [entity_id]).first
    return false unless row && row['articles_indexed_at']

    last = parse_ts(row['articles_indexed_at'])
    return false unless last
    (now - last) < ttl
  end

  # Test helper — drop all cached hits + reset timestamps for an entity.
  def reset_for(kind:, entity_id:)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)
    db.execute('DELETE FROM sports_entity_articles WHERE kind = ? AND entity_id = ?', [kind.to_s, entity_id])
    table = kind_table(kind)
    db.execute("UPDATE #{table} SET articles_indexed_at = NULL WHERE id = ?", [entity_id])
  end

  # FTS5 phrase MATCH on the entity's name. Returns article ids,
  # most-relevant first. Returns [] on FTS5 syntax errors (defensive
  # — unlikely with a quoted phrase, but the cost is zero).
  def fts_search(name)
    phrase = %("#{name.gsub('"', '')}")
    db.execute(<<~SQL, [phrase]).map { |r| r['id'] }
      SELECT a.id
      FROM articles_fts f
      JOIN articles a ON a.id = f.rowid
      WHERE articles_fts MATCH ?
      ORDER BY rank
    SQL
  rescue SQLite3::SQLException
    []
  end

  def stamp_indexed!(kind:, entity_id:, now: Time.now)
    table = kind_table(kind)
    db.execute(
      "UPDATE #{table} SET articles_indexed_at = ? WHERE id = ?",
      [now.utc.strftime('%Y-%m-%d %H:%M:%S'), entity_id]
    )
  end

  def kind_table(kind)
    case kind.to_s
    when 'player' then 'sports_players'
    when 'team'   then 'sports_teams'
    else raise ArgumentError, "unknown kind: #{kind.inspect}"
    end
  end

  def parse_ts(value)
    return value if value.is_a?(Time)
    Time.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
