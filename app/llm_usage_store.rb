require_relative 'database'
require_relative 'dev_stats'

# Append-only log of every successful LLM call made through a
# user-facing route. Written by the route handlers (/triage, /chat,
# /article/:uid/summarize/llm, /digests/:id/summarize); read by
# LlmGuard to enforce per-user and global token budgets.
#
# Cost is recorded at insert time using DevStats.cost_for so the
# admin view + circuit-breaker don't have to re-derive it.
module LlmUsageStore
  module_function

  def db
    Database.connection
  end

  def record!(user_id:, route:, model:, input_tokens:, output_tokens:)
    cost = DevStats.cost_for(model.to_s, input_tokens.to_i, output_tokens.to_i, 0, 0)
    db.execute(
      <<~SQL,
        INSERT INTO llm_usage (user_id, route, model, input_tokens, output_tokens, cost_usd, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      [user_id.to_i, route.to_s, model.to_s, input_tokens.to_i, output_tokens.to_i, cost, Time.now.utc.iso8601]
    )
  end

  # Tokens (input + output) spent by one user in the last 24h.
  def tokens_last_24h(user_id)
    cutoff = (Time.now.utc - 86_400).iso8601
    row = db.execute(
      'SELECT COALESCE(SUM(input_tokens + output_tokens), 0) AS t FROM llm_usage WHERE user_id = ? AND created_at >= ?',
      [user_id.to_i, cutoff]
    ).first
    row ? row['t'].to_i : 0
  end

  # Tokens (input + output) spent by all users in the last hour.
  # Used by the global circuit-breaker.
  def tokens_last_hour_global
    cutoff = (Time.now.utc - 3_600).iso8601
    row = db.execute(
      'SELECT COALESCE(SUM(input_tokens + output_tokens), 0) AS t FROM llm_usage WHERE created_at >= ?',
      [cutoff]
    ).first
    row ? row['t'].to_i : 0
  end

  def cost_last_hour_global
    cutoff = (Time.now.utc - 3_600).iso8601
    row = db.execute(
      'SELECT COALESCE(SUM(cost_usd), 0.0) AS c FROM llm_usage WHERE created_at >= ?',
      [cutoff]
    ).first
    row ? row['c'].to_f : 0.0
  end

  # Per-user usage in the last 24h, newest spenders first. Powers the
  # /admin/llm-quota table.
  def usage_last_24h_by_user
    cutoff = (Time.now.utc - 86_400).iso8601
    db.execute(<<~SQL, [cutoff])
      SELECT user_id,
             COUNT(*)                    AS calls,
             SUM(input_tokens)           AS input_tokens,
             SUM(output_tokens)          AS output_tokens,
             SUM(input_tokens + output_tokens) AS total_tokens,
             SUM(cost_usd)               AS cost_usd
      FROM llm_usage
      WHERE created_at >= ?
      GROUP BY user_id
      ORDER BY total_tokens DESC
    SQL
  end
end
