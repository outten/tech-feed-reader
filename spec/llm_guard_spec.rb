require_relative 'spec_helper'
require_relative '../app/llm_guard'
require_relative '../app/llm_usage_store'

RSpec.describe LlmGuard do
  around do |example|
    saved = ENV.to_h.slice(
      'LLM_ENABLED',
      'LLM_USER_DAILY_TOKEN_BUDGET',
      'LLM_GLOBAL_HOURLY_TOKEN_BUDGET',
      'LLM_GLOBAL_HOURLY_COST_BUDGET'
    )
    example.run
  ensure
    %w[LLM_ENABLED LLM_USER_DAILY_TOKEN_BUDGET LLM_GLOBAL_HOURLY_TOKEN_BUDGET LLM_GLOBAL_HOURLY_COST_BUDGET].each do |k|
      saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k)
    end
  end

  it 'allows the call when no usage has been recorded' do
    decision = described_class.check(user_id: 1)
    expect(decision.denied?).to eq(false)
  end

  it 'denies when LLM_ENABLED=false regardless of usage' do
    ENV['LLM_ENABLED'] = 'false'
    decision = described_class.check(user_id: 1)
    expect(decision.denied?).to eq(true)
    expect(decision.reason).to eq(:disabled)
  end

  it 'denies once the per-user daily token budget is reached' do
    ENV['LLM_USER_DAILY_TOKEN_BUDGET'] = '1000'
    LlmUsageStore.record!(user_id: 1, route: '/triage', model: 'claude-sonnet-4-6',
                          input_tokens: 600, output_tokens: 500)
    decision = described_class.check(user_id: 1)
    expect(decision.denied?).to eq(true)
    expect(decision.reason).to eq(:user)
  end

  it 'denies via the global hourly token circuit-breaker' do
    ENV['LLM_GLOBAL_HOURLY_TOKEN_BUDGET'] = '500'
    ENV['LLM_USER_DAILY_TOKEN_BUDGET']   = '100000'  # not the limit being tested
    LlmUsageStore.record!(user_id: 2, route: '/chat', model: 'claude-sonnet-4-6',
                          input_tokens: 300, output_tokens: 300)
    decision = described_class.check(user_id: 1)
    expect(decision.denied?).to eq(true)
    expect(decision.reason).to eq(:global)
  end

  it 'denies via the global hourly cost circuit-breaker even when token budget is fine' do
    ENV['LLM_GLOBAL_HOURLY_COST_BUDGET'] = '0.01'
    ENV['LLM_GLOBAL_HOURLY_TOKEN_BUDGET'] = '100000000'
    # claude-opus-4-7 at 1k input + 1k output is well above $0.01
    LlmUsageStore.record!(user_id: 2, route: '/triage', model: 'claude-opus-4-7',
                          input_tokens: 1_000, output_tokens: 1_000)
    decision = described_class.check(user_id: 1)
    expect(decision.denied?).to eq(true)
    expect(decision.reason).to eq(:global)
  end

  it 'does not count usage older than 24h against the per-user budget' do
    ENV['LLM_USER_DAILY_TOKEN_BUDGET'] = '1000'
    old = (Time.now.utc - 90_000).iso8601  # 25 hours ago
    Database.connection.execute(
      'INSERT INTO llm_usage (user_id, route, model, input_tokens, output_tokens, cost_usd, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [1, '/triage', 'claude-sonnet-4-6', 5_000, 5_000, 0.10, old]
    )
    decision = described_class.check(user_id: 1)
    expect(decision.denied?).to eq(false)
  end
end
