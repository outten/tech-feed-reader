require_relative 'spec_helper'
require_relative '../app/feed_catalog'

# STUFF #52.3 — NPB / KBO / BWF league entries now have RSS bridge
# entries in SPORTS_LEAGUE_FEEDS, and the URLs they point at are
# present in FeedCatalog::CATALOG so the /sports/feeds/subscribe
# endpoint (which 422s on URLs not in CATALOG) accepts them.
RSpec.describe 'SPORTS_LEAGUE_FEEDS bridge — #52.3 additions' do
  describe 'baseball (NPB + KBO)' do
    it 'returns at least one feed for NPB' do
      entries = FeedCatalog.feeds_for_sports_league('npb')
      expect(entries).not_to be_empty
      expect(entries.map { |e| e[:url] }).to include(
        'https://feeds.bbci.co.uk/sport/baseball/rss.xml'
      )
    end

    it 'returns the dedicated KBO feed for KBO' do
      entries = FeedCatalog.feeds_for_sports_league('kbo')
      expect(entries.map { |e| e[:url] }).to include('https://mykbo.net/feed/')
    end
  end

  describe 'badminton (BWF mens + womens)' do
    it 'binds the BWF + Badzine feeds to bwf-mens' do
      entries = FeedCatalog.feeds_for_sports_league('bwf-mens')
      expect(entries.map { |e| e[:url] }).to contain_exactly(
        'https://bwfbadminton.com/news/feed/',
        'https://www.badzine.net/feed/'
      )
    end

    it 'binds the same feeds to bwf-womens' do
      entries = FeedCatalog.feeds_for_sports_league('bwf-womens')
      expect(entries.map { |e| e[:url] }).to contain_exactly(
        'https://bwfbadminton.com/news/feed/',
        'https://www.badzine.net/feed/'
      )
    end
  end

  describe 'catalog integrity for the new entries' do
    %w[
      https://feeds.bbci.co.uk/sport/baseball/rss.xml
      https://mykbo.net/feed/
      https://en.yna.co.kr/RSS/sports.xml
      https://bwfbadminton.com/news/feed/
      https://www.badzine.net/feed/
    ].each do |url|
      it "registers #{url} in FeedCatalog::CATALOG" do
        expect(FeedCatalog.find_by_url(url)).not_to be_nil
      end
    end
  end
end
