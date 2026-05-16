require_relative 'llm_usage_store'

# Pre-flight check for every user-initiated LLM call. Three layers:
#
#   1. LLM_ENABLED feature flag — env-driven kill switch. Lets us
#      shut all four LLM routes off without a redeploy if costs spike.
#   2. Global hourly circuit-breaker — caps the *total* spend across
#      all users in the last hour. Triggers when either the token or
#      cost ceiling is crossed. Protects against a stampede.
#   3. Per-user 24h token quota — the day-to-day fairness rule.
#      Stops one user from monopolising the budget.
#
# Returns a small result object (LlmGuard::Decision). Route handlers
# call `.denied?` and dispatch accordingly; the message field is
# safe to surface to the user (no internals leaked).
module LlmGuard
  Decision = Struct.new(:denied, :reason, :message, keyword_init: true) do
    def denied?
      denied
    end
  end

  ALLOWED = Decision.new(denied: false, reason: nil, message: nil).freeze

  # Defaults are conservative for a public deploy. Override via env.
  DEFAULT_USER_DAILY_TOKENS    = 200_000     # ~$3 of Sonnet I/O per user per day
  DEFAULT_GLOBAL_HOURLY_TOKENS = 2_000_000
  DEFAULT_GLOBAL_HOURLY_COST   = 5.00

  module_function

  def enabled?
    ENV.fetch('LLM_ENABLED', 'true').to_s.downcase != 'false'
  end

  def user_daily_token_budget
    Integer(ENV.fetch('LLM_USER_DAILY_TOKEN_BUDGET', DEFAULT_USER_DAILY_TOKENS))
  end

  def global_hourly_token_budget
    Integer(ENV.fetch('LLM_GLOBAL_HOURLY_TOKEN_BUDGET', DEFAULT_GLOBAL_HOURLY_TOKENS))
  end

  def global_hourly_cost_budget
    Float(ENV.fetch('LLM_GLOBAL_HOURLY_COST_BUDGET', DEFAULT_GLOBAL_HOURLY_COST))
  end

  def check(user_id:)
    unless enabled?
      return Decision.new(denied: true, reason: :disabled,
                          message: 'LLM features are temporarily disabled by the operator.')
    end

    g_tokens = LlmUsageStore.tokens_last_hour_global
    g_cost   = LlmUsageStore.cost_last_hour_global
    if g_tokens >= global_hourly_token_budget || g_cost >= global_hourly_cost_budget
      return Decision.new(denied: true, reason: :global,
                          message: 'LLM features are temporarily paused — the hourly budget for the service has been reached. Try again later.')
    end

    u_tokens = LlmUsageStore.tokens_last_24h(user_id)
    if u_tokens >= user_daily_token_budget
      return Decision.new(denied: true, reason: :user,
                          message: "Daily LLM quota reached (#{u_tokens}/#{user_daily_token_budget} tokens). Resets 24h after your earliest call today.")
    end

    ALLOWED
  end
end
