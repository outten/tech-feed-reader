require_relative 'spec_helper'
require_relative '../app/tracing'

RSpec.describe Tracing do
  describe 'in test env' do
    it 'reports SDK as inactive (so RSpec doesn\'t boot a real exporter)' do
      expect(Tracing.enabled?).to be false
    end

    it 'reports OTLP exporter as disabled' do
      expect(Tracing.otlp_enabled?).to be false
    end

    it 'still exposes a working tracer (the API package\'s no-op)' do
      expect { Tracing.tracer }.not_to raise_error
    end

    it 'in_span yields and returns the block value even when the SDK is no-op' do
      result = Tracing.in_span('test.span') { |_s| 42 }
      expect(result).to eq(42)
    end
  end
end

RSpec.describe Tracing::Recorder do
  before { Tracing::Recorder.clear! }
  after  { Tracing::Recorder.clear! }

  it 'records spans newest-first' do
    s1 = double('span', hex_trace_id: 'a' * 32)
    s2 = double('span', hex_trace_id: 'b' * 32)
    Tracing::Recorder.record(s1)
    Tracing::Recorder.record(s2)
    expect(Tracing::Recorder.spans).to eq([s2, s1])
    expect(Tracing::Recorder.count).to eq(2)
  end

  it 'evicts oldest entries past capacity (ring-buffer behaviour)' do
    cap = Tracing::Recorder.capacity
    (cap + 5).times { |i| Tracing::Recorder.record(double("span#{i}")) }
    expect(Tracing::Recorder.count).to eq(cap)
  end

  it 'clear! empties the buffer' do
    Tracing::Recorder.record(double('span'))
    Tracing::Recorder.clear!
    expect(Tracing::Recorder.spans).to eq([])
    expect(Tracing::Recorder.count).to eq(0)
  end
end

RSpec.describe Tracing::RecorderProcessor do
  before { Tracing::Recorder.clear! }
  after  { Tracing::Recorder.clear! }

  it 'on_finish hands the span_data to the recorder when the span is sampled' do
    span_data = double('span_data')
    span = double(
      'span',
      to_span_data: span_data,
      context: double('ctx', trace_flags: double('flags', sampled?: true))
    )
    described_class.new.on_finish(span)
    expect(Tracing::Recorder.spans).to eq([span_data])
  end

  it 'on_finish skips unsampled spans' do
    span = double(
      'span',
      to_span_data: double('data'),
      context: double('ctx', trace_flags: double('flags', sampled?: false))
    )
    described_class.new.on_finish(span)
    expect(Tracing::Recorder.count).to eq(0)
  end

  it 'never raises if the recorder hits an internal error' do
    span = double('span')
    allow(span).to receive(:context).and_raise(RuntimeError, 'boom')
    expect { described_class.new.on_finish(span) }.not_to raise_error
  end

  it 'force_flush + shutdown return SUCCESS without raising' do
    p = described_class.new
    expect(p.force_flush).to eq(0)
    expect(p.shutdown).to eq(0)
  end
end
