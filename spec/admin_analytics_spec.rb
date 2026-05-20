require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/pageview_section'
require_relative '../app/pageviews_store'
require_relative '../app/users_store'

# STUFF #48.1 — admin usage analytics. Four surfaces:
#   1. PageviewSection bucketing (path → section / ignore?)
#   2. PageviewsStore CRUD + aggregations + prune
#   3. RequestLogMiddleware persists rows per dynamic GET
#   4. /admin/analytics + /admin/users routes
RSpec.describe 'Admin analytics (STUFF #48.1)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'PageviewSection.for_path' do
    {
      '/articles'              => 'articles',
      '/articles?state=unread' => 'articles', # bare path — query strings are stripped by the middleware caller anyway
      '/article/abc123'        => 'articles',
      '/bookmarks'             => 'articles',
      '/podcasts'              => 'podcasts',
      '/podcast/abc'           => 'podcasts',
      '/bus'                   => 'podcasts',
      '/youtube'               => 'youtube',
      '/youtube/123'           => 'youtube',
      '/sports'                => 'sports',
      '/sports/tennis'         => 'sports',
      '/sports/team/eagles'    => 'sports',
      '/feeds'                 => 'feeds',
      '/tags'                  => 'feeds',
      '/admin'                 => 'admin',
      '/admin/analytics'       => 'admin',
      '/sign-in'               => 'auth',
      '/sign-up'               => 'auth',
      '/account'               => 'auth',
      '/api/auth/register'     => 'auth',
      '/'                      => 'home',
      '/about'                 => 'home'
    }.each do |path, expected|
      it "buckets #{path.inspect} as #{expected.inspect}" do
        # The middleware passes only PATH_INFO (no query string) to for_path.
        bare = path.split('?').first
        expect(PageviewSection.for_path(bare)).to eq(expected)
      end
    end

    it 'returns nil for unknown paths' do
      expect(PageviewSection.for_path('/random-thing')).to be_nil
    end
  end

  describe 'PageviewSection.ignore?' do
    %w[/health /metrics /style.css /global-player.js /img/foo.png /api/chat /api/chat/poll].each do |path|
      it "ignores #{path.inspect}" do
        expect(PageviewSection.ignore?(path)).to be(true)
      end
    end

    %w[/articles /podcasts /sports /admin].each do |path|
      it "does NOT ignore #{path.inspect}" do
        expect(PageviewSection.ignore?(path)).to be(false)
      end
    end
  end

  describe 'PageviewsStore' do
    it 'records + reads back a row' do
      PageviewsStore.record!(user_id: 1, path: '/articles', section: 'articles', status: 200)
      expect(PageviewsStore.total).to eq(1)
    end

    it 'aggregates daily totals + section totals across a window' do
      3.times { PageviewsStore.record!(user_id: 1, path: '/articles', section: 'articles', status: 200) }
      2.times { PageviewsStore.record!(user_id: 1, path: '/podcasts', section: 'podcasts', status: 200) }
      1.times { PageviewsStore.record!(user_id: nil, path: '/other',  section: nil,         status: 200) }

      expect(PageviewsStore.total(days: 14)).to eq(6)
      sections = PageviewsStore.section_totals(days: 14)
      expect(sections.find { |s| s['section'] == 'articles' }['count']).to eq(3)
      expect(sections.find { |s| s['section'] == 'podcasts' }['count']).to eq(2)
      expect(sections.find { |s| s['section'] == 'other'    }['count']).to eq(1)
    end

    it 'prunes rows older than the retention window' do
      # Insert one fresh row + one ancient row by writing the timestamp directly.
      PageviewsStore.record!(user_id: 1, path: '/articles', section: 'articles', status: 200)
      Database.connection.execute(
        "INSERT INTO pageviews(path, section, status, occurred_at) VALUES ('/old', 'articles', 200, ?)",
        ['2024-01-01T00:00:00Z']
      )
      expect(PageviewsStore.total(days: 9000)).to eq(2)
      deleted = PageviewsStore.prune_older_than!(days: 90)
      expect(deleted).to eq(1)
      expect(PageviewsStore.total(days: 9000)).to eq(1)
    end
  end

  describe 'RequestLogMiddleware persistence' do
    # The middleware is wired via Rack::Builder ahead of Sinatra (see
    # the bottom of app/main.rb), so Rack::Test.get goes around it.
    # Test the middleware directly, matching the pattern in
    # spec/metrics_spec.rb.
    let(:inner) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
    let(:mw)    { RequestLogMiddleware::App.new(inner) }

    def env_for(method:, path:, session: {})
      Rack::MockRequest.env_for(path, method: method).merge('rack.session' => session)
    end

    it 'inserts a row per dynamic GET' do
      expect { mw.call(env_for(method: 'GET', path: '/articles', session: { user_id: 1 })) }
        .to change { PageviewsStore.total }.by(1)
    end

    it 'attributes the row to the signed-in user via the session' do
      mw.call(env_for(method: 'GET', path: '/articles', session: { user_id: 7 }))
      row = Database.connection.execute('SELECT user_id FROM pageviews ORDER BY id DESC LIMIT 1').first
      expect(row['user_id'].to_i).to eq(7)
    end

    it 'records anonymous pageviews (user_id NULL)' do
      mw.call(env_for(method: 'GET', path: '/about'))
      row = Database.connection.execute('SELECT user_id FROM pageviews ORDER BY id DESC LIMIT 1').first
      expect(row['user_id']).to be_nil
    end

    it 'skips noise paths' do
      expect {
        mw.call(env_for(method: 'GET', path: '/health'))
        mw.call(env_for(method: 'GET', path: '/metrics'))
        mw.call(env_for(method: 'GET', path: '/style.css'))
      }.not_to(change { PageviewsStore.total })
    end

    it 'skips non-GET requests' do
      expect { mw.call(env_for(method: 'POST', path: '/api/articles/bulk')) }
        .not_to(change { PageviewsStore.total })
    end
  end

  describe 'GET /admin/analytics' do
    before do
      # Seed a couple of pageviews so the chart blocks render.
      3.times { PageviewsStore.record!(user_id: 1, path: '/articles', section: 'articles', status: 200) }
    end

    it 'renders the summary tiles + per-section table' do
      get '/admin/analytics'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Total users', 'Pageviews', 'By section')
      expect(last_response.body).to include('articles')
    end

    it 'opportunistically prunes rows older than 90 days' do
      Database.connection.execute(
        "INSERT INTO pageviews(path, section, status, occurred_at) VALUES ('/old', 'articles', 200, ?)",
        ['2024-01-01T00:00:00Z']
      )
      expect { get '/admin/analytics' }.to change { PageviewsStore.total(days: 9000) }.by(-1)
    end

    it 'clamps ?days to 1..90' do
      get '/admin/analytics?days=500'
      expect(last_response.body).to include('last <strong>90</strong> days')
      get '/admin/analytics?days=0'
      expect(last_response.body).to include('last <strong>1</strong> days')
    end
  end

  describe 'GET /admin/users' do
    it 'renders the user list with passkey + recovery-code columns' do
      get '/admin/users'
      expect(last_response.status).to eq(200)
      # The spec_helper seeds user 1 (t-money), so the table should
      # always have at least one row.
      expect(last_response.body).to include('t-money')
      expect(last_response.body).to include('Passkeys', 'Recovery codes')
    end
  end

  describe 'admin index link' do
    it 'mentions /admin/analytics + /admin/users in the sub-pages section' do
      get '/admin'
      expect(last_response.body).to include('/admin/analytics')
      expect(last_response.body).to include('/admin/users')
    end
  end
end
