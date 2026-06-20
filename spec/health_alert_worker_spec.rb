require_relative 'spec_helper'
require_relative '../app/workers/health_alert_worker'

# Pushes ntfy alerts on a health state transition (pre-launch ops alerting).
# Redis is
# disabled in the test env, so the transition-state helpers are stubbed and
# these assert the worker's decision logic (what it flags, when it pushes).
RSpec.describe HealthAlertWorker do
  let(:worker) { described_class.new }

  describe '#collect_problems' do
    before do
      allow(worker).to receive(:newest_fetch_age_hours).and_return(0.2)
      allow(worker).to receive(:dead_set_size).and_return(0)
    end

    it 'is empty when the DB is reachable, feeds are fresh, dead set small' do
      expect(worker.collect_problems).to eq([])
    end

    it 'flags a stalled feed pipeline when the newest fetch exceeds FRESH_HOURS' do
      allow(worker).to receive(:newest_fetch_age_hours).and_return(HealthAlertWorker::FRESH_HOURS + 2)
      expect(worker.collect_problems.join).to match(/Feed pipeline stalled/)
    end

    it 'flags a growing Sidekiq dead set' do
      allow(worker).to receive(:dead_set_size).and_return(HealthAlertWorker::DEAD_MAX + 1)
      expect(worker.collect_problems.join).to match(/dead set/)
    end

    it 'flags an unreachable database' do
      allow(Database).to receive(:connection).and_raise(StandardError, 'no db')
      expect(worker.collect_problems.join).to match(/Postgres unreachable/)
    end
  end

  describe '#perform (transition-based alerting)' do
    before { allow(worker).to receive(:store_state) }

    it 'pushes a PROBLEM alert when transitioning ok→bad' do
      allow(worker).to receive(:collect_problems).and_return(['Postgres unreachable'])
      allow(worker).to receive(:current_state).and_return(nil)
      expect(Notifier).to receive(:push).with(hash_including(title: 'Feeder health: PROBLEM'))
      worker.perform
    end

    it 'pushes a recovered alert when transitioning bad→ok' do
      allow(worker).to receive(:collect_problems).and_return([])
      allow(worker).to receive(:current_state).and_return('bad')
      expect(Notifier).to receive(:push).with(hash_including(title: 'Feeder health: recovered'))
      worker.perform
    end

    it 'stays silent when the state has not changed (bad→bad)' do
      allow(worker).to receive(:collect_problems).and_return(['x'])
      allow(worker).to receive(:current_state).and_return('bad')
      expect(Notifier).not_to receive(:push)
      worker.perform
    end

    it 'stays silent on a healthy steady state (ok→ok)' do
      allow(worker).to receive(:collect_problems).and_return([])
      allow(worker).to receive(:current_state).and_return('ok')
      expect(Notifier).not_to receive(:push)
      worker.perform
    end
  end
end
