require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/tracing'

RSpec.describe 'GET /admin/traces' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  before { Tracing::Recorder.clear! }
  after  { Tracing::Recorder.clear! }

  # Build a SpanData-shaped double. Just enough fields for the view to
  # render — we don't need to spin up the SDK to test the route shape.
  def make_span(name:, trace_id:, span_id:, parent_id: OpenTelemetry::Trace::INVALID_SPAN_ID,
                start_ns: 1, end_ns: 1_000_000, attrs: {}, status_code: nil, status_desc: '')
    status_code ||= OpenTelemetry::Trace::Status::OK
    double(
      "span_data:#{name}",
      name:             name,
      kind:             :internal,
      hex_trace_id:     trace_id,
      hex_span_id:      span_id,
      parent_span_id:   parent_id,
      start_timestamp:  start_ns,
      end_timestamp:    end_ns,
      attributes:       attrs,
      status:           double('status', code: status_code, description: status_desc)
    )
  end

  it 'renders the empty state when no spans are buffered' do
    get '/admin/traces'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Traces')
    expect(last_response.body).to include('No spans recorded yet')
  end

  it 'renders configuration block with capacity + count + service name' do
    get '/admin/traces'
    expect(last_response.body).to include('Service name')
    expect(last_response.body).to include('tech-feed-reader')
    expect(last_response.body).to include("0 / #{Tracing::Recorder.capacity} spans buffered")
  end

  it 'groups spans by trace and renders root name + duration' do
    trace_id = 'a' * 32
    Tracing::Recorder.record(make_span(
      name: 'feed.fetch', trace_id: trace_id, span_id: '1' * 16,
      start_ns: 0, end_ns: 50_000_000,
      attrs: { 'feed.id' => 7, 'feed.url' => 'https://example.com/rss' }
    ))
    Tracing::Recorder.record(make_span(
      name: 'pg.query', trace_id: trace_id, span_id: '2' * 16,
      parent_id: '1' * 16,
      start_ns: 5_000_000, end_ns: 8_000_000
    ))

    get '/admin/traces'
    expect(last_response.status).to eq(200)
    body = last_response.body
    expect(body).to include('feed.fetch')
    expect(body).to include('pg.query')
    expect(body).to include('https://example.com/rss')
    expect(body).to include('feed.id')
    # Root span has no offset, child should show +5.0ms
    expect(body).to include('+5.0ms')
  end

  it 'filters to one trace via ?trace=<hex_trace_id>' do
    keep_id = 'k' * 32
    drop_id = 'd' * 32
    Tracing::Recorder.record(make_span(name: 'kept.root',  trace_id: keep_id, span_id: '1' * 16))
    Tracing::Recorder.record(make_span(name: 'dropped.root', trace_id: drop_id, span_id: '2' * 16))

    get "/admin/traces?trace=#{keep_id}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('kept.root')
    expect(last_response.body).not_to include('dropped.root')
    expect(last_response.body).to include('All traces')
  end

  it 'shows the OTLP-disabled hint by default in test env' do
    get '/admin/traces'
    expect(last_response.body).to include('No external exporter configured')
  end

  it 'flags error spans with the error badge + description' do
    Tracing::Recorder.record(make_span(
      name: 'feed.fetch',
      trace_id: 'e' * 32, span_id: '1' * 16,
      status_code: OpenTelemetry::Trace::Status::ERROR,
      status_desc: 'HTTP 500'
    ))
    get '/admin/traces'
    expect(last_response.body).to include('error')
    expect(last_response.body).to include('HTTP 500')
  end
end
