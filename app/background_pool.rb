require 'json'
require_relative 'database'
require_relative 'logger'
require_relative 'providers/http_client'

# Stored pool of Picsum image IDs that page-background.js rotates
# through for the page background. Empty pool = the JS falls back to
# its bundled curated set; calling refresh! wipes the table and
# writes a fresh batch fetched from Picsum's /v2/list endpoint.
#
# Default fallback is the same small curated set baked into
# page-background.js, kept in sync via DEFAULT_IDS below so the JS
# fallback and the seed-on-empty behaviour stay aligned.
module BackgroundPool
  # Curated nature-themed Picsum IDs used when the table is empty.
  # Keep in sync with public/page-background.js's IDS array.
  DEFAULT_IDS = [10, 15, 28, 29, 1015, 1018, 1019, 1037, 1043, 1044, 1059].freeze
  POOL_TARGET_SIZE = 12
  PICSUM_LIST_URL = 'https://picsum.photos/v2/list?page=1&limit=100'.freeze

  RefreshError = Class.new(StandardError)

  module_function

  # Picsum IDs the page-background JS should rotate through. Returns
  # the stored pool when populated, else falls back to the curated
  # default — so a fresh install still has working backgrounds before
  # the user has clicked "Refresh pool" in /admin.
  def ids
    rows = entries
    return DEFAULT_IDS.dup if rows.empty?
    rows.map { |r| r['picsum_id'] }
  end

  # Full rows (id + author + unsplash_url + added_at), newest first.
  # Used by the /admin/backgrounds page to render thumbnails + "by X"
  # next to each entry.
  def entries
    Database.connection.execute(<<~SQL)
      SELECT picsum_id, author, unsplash_url, added_at
      FROM background_pool
      ORDER BY added_at DESC, picsum_id DESC
    SQL
  end

  def count
    Database.connection.execute('SELECT COUNT(*) AS c FROM background_pool').first['c']
  end

  # Wipe + replace with `count` fresh random picks from Picsum's
  # /v2/list. Atomic — the wipe and the inserts run inside a single
  # SQLite transaction so a partial fetch failure leaves the existing
  # pool intact.
  #
  # Returns an integer (the number of rows inserted).
  def refresh!(count: POOL_TARGET_SIZE, candidates: nil)
    candidates ||= fetch_candidates
    raise RefreshError, 'Picsum returned no candidates' if candidates.empty?

    sample = candidates.shuffle.first(count)
    db = Database.connection
    db.transaction do
      db.execute('DELETE FROM background_pool')
      sample.each do |entry|
        db.execute(<<~SQL, [entry[:id].to_i, entry[:author].to_s, entry[:url].to_s])
          INSERT INTO background_pool (picsum_id, author, unsplash_url)
          VALUES (?, ?, ?)
        SQL
      end
    end
    AppLogger.info('background_pool_refreshed', inserted: sample.length, source: 'picsum/v2/list')
    sample.length
  end

  # Fetches Picsum's /v2/list and returns an array of
  # { id:, author:, url: } hashes. Public so specs can stub it.
  # Wraps any HTTP / parse failure in a RefreshError so the calling
  # route can surface a clean message.
  def fetch_candidates(url: PICSUM_LIST_URL)
    response = Providers::HttpClient.get(url)
    code = response.code.to_i
    raise RefreshError, "HTTP #{code} from #{url}" unless (200..299).include?(code)
    parsed = JSON.parse(response.body)
    Array(parsed).map do |row|
      { id: row['id'], author: row['author'], url: row['url'] }
    end
  rescue JSON::ParserError => e
    raise RefreshError, "Picsum response was not valid JSON: #{e.message}"
  end
end
