require_relative 'database'

# Wrapper around the `summaries` table. One row per article. The two
# summary kinds (extractive, llm) live side-by-side so the same row
# survives both backends — extractive is generated automatically on
# import, llm is opt-in (Tier 2 K, lands later) and the user clicks
# "summarize with Claude" on /article/:uid.
#
# Lazy: rows are created on first .upsert. .find returns nil when no
# summary exists; callers can render the no-summary state cleanly.
module SummaryStore
  module_function

  def find(article_id)
    db.execute('SELECT * FROM summaries WHERE article_id = ?', [article_id]).first
  end

  def has_extractive?(article_id)
    row = find(article_id)
    !row.nil? && !row['extractive'].to_s.empty?
  end

  # Insert or update a summary row. Only the supplied kwargs overwrite —
  # passing extractive: 'foo' leaves an existing llm field intact.
  def upsert(article_id, extractive: nil, llm: nil, llm_model: nil)
    current = find(article_id)
    next_extractive = extractive.nil? ? (current && current['extractive']) : extractive
    next_llm        = llm.nil?        ? (current && current['llm'])        : llm
    next_model      = llm_model.nil?  ? (current && current['llm_model'])  : llm_model

    db.execute(<<~SQL, [article_id, next_extractive, next_llm, next_model])
      INSERT OR REPLACE INTO summaries(article_id, extractive, llm, llm_model)
      VALUES (?, ?, ?, ?)
    SQL
    find(article_id)
  end

  def remove(article_id)
    db.execute('DELETE FROM summaries WHERE article_id = ?', [article_id])
    db.changes.positive?
  end

  class << self
    private

    def db
      Database.connection
    end
  end
end
