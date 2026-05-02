require_relative 'spec_helper'
require 'date'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/topic_clusters'

RSpec.describe TopicClusters do
  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }

  def insert(uid, title, content_text, day_offset = 0)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://example.com/#{uid}", author: nil,
      published_at: (Date.today - day_offset).to_s + 'T12:00:00Z',
      content_html: "<p>#{content_text}</p>", content_text: content_text
    }])
  end

  describe '.recent' do
    it 'returns [] when no articles fall in the window' do
      insert('a' * 12, 'Old', 'kubernetes networking pods', 100)
      expect(TopicClusters.recent(days: 14)).to eq([])
    end

    it 'surfaces terms shared by min_articles or more articles' do
      insert('a' * 12, 'K8s 1', 'Kubernetes networking is hard. Pods and services.')
      insert('b' * 12, 'K8s 2', 'Kubernetes scheduling and pods explained.')
      insert('c' * 12, 'K8s 3', 'Kubernetes operators package operational know-how.')
      insert('d' * 12, 'Solo', 'A standalone post about cooking and recipes.')

      clusters = TopicClusters.recent(days: 14, min_articles: 2)
      terms = clusters.map { |c| c[:term] }
      expect(terms).to include('kubernetes')
      expect(terms).not_to include('cooking')
    end

    it 'sorts clusters by article count desc, then alphabetically' do
      3.times { |i| insert("a#{i}".ljust(12, '0'), 'A', 'kubernetes networking pods replicas') }
      2.times { |i| insert("b#{i}".ljust(12, '0'), 'B', 'rust borrow checker memory safety') }

      clusters = TopicClusters.recent(days: 14, min_articles: 2)
      expect(clusters.first[:count]).to be >= clusters.last[:count]
      expect(clusters.first[:term]).to eq('kubernetes')
    end

    it 'each cluster carries up to 3 example articles' do
      5.times do |i|
        insert("k#{i}".ljust(12, '0'), "K post #{i}",
               'kubernetes pods replicas scheduling operators autoscaling')
      end
      cluster = TopicClusters.recent(days: 14, min_articles: 2).find { |c| c[:term] == 'kubernetes' }
      expect(cluster[:articles].length).to eq(3)
      expect(cluster[:articles].first['title']).to start_with('K post')
    end

    it 'honours the limit kwarg' do
      # Build several distinct topics each with enough articles to qualify.
      %w[kubernetes rust python javascript typescript].each_with_index do |topic, idx|
        3.times do |i|
          uid = "#{topic[0]}#{idx}#{i}".ljust(12, '0')
          insert(uid, "#{topic} post #{i}", ([topic] * 5).join(' ') + ' is interesting.')
        end
      end

      expect(TopicClusters.recent(days: 14, min_articles: 2, limit: 3).length).to eq(3)
    end

    it 'excludes articles outside the window even if their term is hot inside it' do
      3.times { |i| insert("k#{i}".ljust(12, '0'), 'K', 'kubernetes networking pods', 30) }
      insert('a' * 12, 'In', 'kubernetes is great', 1)

      cluster = TopicClusters.recent(days: 14, min_articles: 2).find { |c| c[:term] == 'kubernetes' }
      expect(cluster).to be_nil  # only 1 in-window article, below min_articles
    end
  end
end
