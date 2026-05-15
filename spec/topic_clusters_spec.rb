require_relative 'spec_helper'
require 'date'
require 'json'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/topic_clusters'

RSpec.describe TopicClusters do
  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }

  def insert(uid, title, content_text, day_offset = 0, categories: nil)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://example.com/#{uid}", author: nil,
      published_at: (Date.today - day_offset).to_s + 'T12:00:00Z',
      content_html: "<p>#{content_text}</p>", content_text: content_text,
      categories: categories ? JSON.generate(categories) : nil
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

    # STUFF #28 — none of the user-reported noise tokens (com, https,
    # can, said, comments, instagram) should surface even when they
    # would have a high raw frequency in the body text.
    it 'does not surface noise tokens from boilerplate prose / bare URLs' do
      noise_body = 'You can read more at https://www.example.com/article. ' \
                   'The CEO said the plan was solid; sources told us so. ' \
                   'Subscribe to our newsletter, follow us on Instagram and Twitter. ' \
                   'Comments are open. ' \
                   'Visit github.com/example/repo for the code.'
      3.times { |i| insert("n#{i}".ljust(12, '0'), 'N', noise_body) }
      # Add a real signal so the corpus is non-empty
      3.times { |i| insert("k#{i}".ljust(12, '0'), 'K', 'kubernetes scheduling pods replicas') }

      terms = TopicClusters.recent(days: 14, min_articles: 2).map { |c| c[:term] }
      %w[com https www can said told comments subscribe instagram twitter github].each do |bad|
        expect(terms).not_to include(bad), "expected '#{bad}' to be filtered, got #{terms.inspect}"
      end
      expect(terms).to include('kubernetes')
    end

    # STUFF #28.2 — publisher categories blend into clusters.
    it 'surfaces a term that comes ONLY from publisher categories (not the body)' do
      3.times do |i|
        insert("p#{i}".ljust(12, '0'), 'P', 'unrelated body text about networking and replicas',
               categories: ['politics'])
      end
      cluster = TopicClusters.recent(days: 14, min_articles: 2).find { |c| c[:term] == 'politics' }
      expect(cluster).not_to be_nil
      expect(cluster[:count]).to eq(3)
    end

    # STUFF #28.3 — category-weighted scoring: when two terms have the
    # same article-count, the one backed by publisher categories wins.
    it 'ranks a category-backed term above a body-only term at equal article count' do
      3.times { |i| insert("c#{i}".ljust(12, '0'), 'C', 'unrelated body text about networking',
                            categories: ['politics']) }
      3.times { |i| insert("b#{i}".ljust(12, '0'), 'B', 'rust borrow checker memory safety') }

      clusters = TopicClusters.recent(days: 14, min_articles: 2)
      pol_idx  = clusters.index { |c| c[:term] == 'politics' }
      rust_idx = clusters.index { |c| c[:term] == 'rust' }
      expect(pol_idx).not_to be_nil
      expect(rust_idx).not_to be_nil
      expect(pol_idx).to be < rust_idx
    end

    # STUFF #28.2 — category brand-noise (e.g. NPR puts "News" on every
    # entry) is filtered explicitly even when the corpus is too small
    # for the ubiquity ceiling to fire.
    it 'filters CATEGORY_STOPWORDS even on tiny corpora' do
      3.times do |i|
        insert("c#{i}".ljust(12, '0'), 'C', 'kubernetes pods replicas',
               categories: ['news', 'kubernetes'])
      end
      terms = TopicClusters.recent(days: 14, min_articles: 2).map { |c| c[:term] }
      expect(terms).not_to include('news')
      expect(terms).to include('kubernetes')
    end

    # STUFF #28.3 — ubiquity ceiling: drop terms appearing in > 50% of
    # the corpus (only when the corpus has enough articles for the
    # ratio to be meaningful, i.e. UBIQUITY_MIN_CORPUS = 20+).
    # STUFF #28.4 — adjacent capitalized words ("Jannik Sinner") cluster
    # together as a single phrase term, not as two competing unigram
    # clusters. The unigram components ("jannik", "sinner") are
    # suppressed for the same article so the phrase wins cleanly.
    it 'surfaces "Jannik Sinner" as a phrase, not as competing jannik / sinner unigrams' do
      3.times do |i|
        insert("j#{i}".ljust(12, '0'), "Sinner #{i}",
               'Tennis is great. Jannik Sinner won again. Jannik Sinner is unstoppable. Jannik Sinner!')
      end
      clusters = TopicClusters.recent(days: 14, min_articles: 2)
      terms    = clusters.map { |c| c[:term] }

      expect(terms).to include('jannik sinner')
      # The unigram components are suppressed for the article that has
      # the phrase, so they fall below min_articles=2.
      expect(terms).not_to include('jannik')
      expect(terms).not_to include('sinner')
    end

    it 'drops a term that appears in too much of a large corpus' do
      # 25-article corpus. "boilerplate" appears in all 25 (frequency 1
      # each). "kubernetes" appears 5x in 5 articles so top_keywords
      # actually surfaces it (insertion-order tie-break on freq=1 would
      # bury single occurrences).
      25.times do |i|
        kub = i < 5 ? ' kubernetes kubernetes kubernetes kubernetes kubernetes' : ''
        insert("u#{i}".to_s.ljust(12, '0'), "U#{i}",
               "boilerplate corpus noise widget gadget#{kub}")
      end

      terms = TopicClusters.recent(days: 14, min_articles: 2, limit: 20).map { |c| c[:term] }
      expect(terms).not_to include('boilerplate'), 'term in 25/25 articles should fail the ubiquity ceiling'
      expect(terms).to include('kubernetes')
    end
  end
end
