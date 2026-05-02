require_relative 'spec_helper'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/recommendation'

RSpec.describe Recommendation do
  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }

  def insert(uid, title, content_text)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://example.com/#{uid}", author: nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: "<p>#{content_text}</p>", content_text: content_text
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe '.top_keywords' do
    it 'returns frequency-ordered non-stopword tokens, longer-than-2-chars only' do
      text = 'kubernetes is great. Kubernetes networking is hard. We use kubernetes daily.'
      kw = Recommendation.top_keywords(text)
      expect(kw.first).to eq('kubernetes')
      expect(kw).not_to include('is')
      expect(kw).not_to include('we')  # stopword
    end

    it 'returns [] for blank input' do
      expect(Recommendation.top_keywords('')).to eq([])
      expect(Recommendation.top_keywords(nil.to_s)).to eq([])
    end

    it 'caps the result list at the limit kwarg' do
      text = 'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda'
      expect(Recommendation.top_keywords(text, limit: 3).length).to eq(3)
    end
  end

  describe '.for_article' do
    it 'ranks articles sharing more distinctive keywords ahead of weak matches' do
      target = insert('a' * 12, 'Ruby framework guide',
                      'Ruby is a language. The Ruby framework Rails is popular. Ruby developers love Rails.')
      insert('b' * 12, 'More Ruby tips',
             'A new Ruby tutorial. The Ruby ecosystem keeps growing. Rails developers swear by Ruby.')
      insert('c' * 12, 'JavaScript fun',
             'JavaScript is a scripting language for browsers. Node.js runs JavaScript on servers.')
      insert('d' * 12, 'Database tips',
             'Indexes, queries, and Ruby ORM patterns are common in Rails applications.')

      ranked = Recommendation.for_article(target, limit: 2).map { |r| r['title'] }
      # The two strong ruby/rails matches outrank the language-only JS post.
      expect(ranked).to contain_exactly('More Ruby tips', 'Database tips')
    end

    it 'excludes the target article from its own recommendations' do
      target = insert('a' * 12, 'Self', 'kubernetes networking is hard. kubernetes scaling is harder.')
      insert('b' * 12, 'Other', 'kubernetes pods and services explained.')

      ids = Recommendation.for_article(target).map { |r| r['id'] }
      expect(ids).not_to include(target['id'])
    end

    it 'returns [] when the article has too little content to extract keywords from' do
      target = insert('a' * 12, 'Empty', '')
      expect(Recommendation.for_article(target)).to eq([])
    end

    it 'returns [] when no other article shares any keyword' do
      target = insert('a' * 12, 'Lonely',
                      'thisisanunusualwordsequence quintessentialdiagonalpurpleflamingosparklingnonsense')
      insert('b' * 12, 'Unrelated', 'a completely different topic about cooking and recipes.')
      expect(Recommendation.for_article(target)).to eq([])
    end

    it 'honours the limit kwarg' do
      target = insert('a' * 12, 'T', 'kubernetes scaling is hard kubernetes is fun')
      6.times do |i|
        insert("b#{i}".ljust(12, '0'), "K post #{i}", 'kubernetes pods replicas autoscaling.')
      end
      expect(Recommendation.for_article(target, limit: 3).length).to eq(3)
    end

    it 'returns [] (no raise) on a nil article' do
      expect(Recommendation.for_article(nil)).to eq([])
    end
  end
end
