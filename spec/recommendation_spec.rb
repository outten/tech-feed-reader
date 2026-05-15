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

    # STUFF #28 — regression for the specific noise tokens the user
    # reported on /topics (com, https, can, said, comments, instagram).
    # URL stripping + expanded stopwords should drop all six.
    describe 'STUFF #28 — noise filtering' do
      it 'strips bare URLs so com/https/www do not leak as tokens' do
        text = 'kubernetes is amazing. See https://www.example.com/post for more. Also https://docs.k8s.io/.'
        kw = Recommendation.top_keywords(text)
        expect(kw).not_to include('com', 'https', 'www', 'docs')
        expect(kw).to include('kubernetes')
      end

      it 'strips emails' do
        text = 'kubernetes pods. Contact alice@example.com or bob@test.org. More kubernetes content.'
        kw = Recommendation.top_keywords(text)
        expect(kw).not_to include('com', 'org', 'example', 'test')
      end

      it 'strips bare hostnames without a protocol' do
        text = 'kubernetes networking. Mirror at github.com/org/repo and docs at kubernetes.io. Pods pods pods.'
        kw = Recommendation.top_keywords(text)
        expect(kw).not_to include('com', 'github', 'org', 'repo')
      end

      it 'filters common journalism verbs (said, told, says)' do
        text = 'The CEO said the merger would close soon. Sources told the FT that the deal said something. He says yes.'
        kw = Recommendation.top_keywords(text)
        expect(kw).not_to include('said', 'told', 'says')
      end

      it 'filters site/social boilerplate (comments, instagram, subscribe)' do
        text = 'Read the comments. Subscribe to our newsletter. Follow us on Instagram and Twitter. Comments are open.'
        kw = Recommendation.top_keywords(text)
        expect(kw).not_to include('comments', 'subscribe', 'newsletter', 'instagram', 'twitter')
      end

      it 'filters common English modals + filler verbs (can, get, make)' do
        text = 'You can get the best results when you make a plan. We get many requests. Can we make it better?'
        kw = Recommendation.top_keywords(text)
        expect(kw).not_to include('can', 'get', 'make')
      end

      it 'preserves real 3+ char domain words (ios, kubernetes, rust)' do
        text = 'iOS 18 ships with new APIs. iOS developers rejoice. The Rust borrow checker is great. Rust everywhere.'
        kw = Recommendation.top_keywords(text)
        expect(kw).to include('ios')
        expect(kw).to include('rust')
      end
    end
  end

  # STUFF #28.4 — proper-noun phrase detection. Adjacent capitalized
  # words form a single phrase so "Jannik Sinner" doesn't split into
  # competing "jannik" and "sinner" clusters on /topics.
  describe '.top_phrases' do
    it 'finds adjacent-capitalized-word phrases, lowercased' do
      text = 'Jannik Sinner won again. Carlos Alcaraz came second. Jannik Sinner is unstoppable.'
      phrases = Recommendation.top_phrases(text)
      expect(phrases).to include('jannik sinner')
      expect(phrases).to include('carlos alcaraz')
    end

    it 'orders phrases by frequency' do
      # Periods between repetitions so the bigram regex finds each
      # occurrence cleanly rather than running into the next bigram.
      text = (['Jannik Sinner.'] * 5 + ['Carlos Alcaraz.'] * 2).join(' ')
      phrases = Recommendation.top_phrases(text)
      expect(phrases.first).to eq('jannik sinner')
    end

    it 'ignores single capitalized words at sentence start (no false positives)' do
      # Each sentence starts with a capital word. None of them form
      # a multi-word phrase, so we should get nothing.
      text = 'The sun is bright. Today is a good day. Tomorrow we run.'
      expect(Recommendation.top_phrases(text)).to eq([])
    end

    it 'rejects phrases containing stopwords (kills sentence-initial leakage)' do
      # "The President" is a sentence-initial capital pair but "the"
      # is a stopword, so it must not be emitted as a phrase.
      text = 'The President spoke. The Congress responded. The President later said no.'
      expect(Recommendation.top_phrases(text)).not_to include('the president')
    end

    it 'strips URLs before phrase extraction' do
      # Trigrams like "New York City" collapse to bigram "new york" by
      # design (see PHRASE_RX comment) — what matters here is that the
      # URL fragments don't sneak in as a phrase.
      text = 'See https://Some.Org/Path for more. Real phrase: New York. New York.'
      phrases = Recommendation.top_phrases(text)
      expect(phrases).to include('new york')
      expect(phrases).not_to include('some org')
    end

    it 'returns [] for empty input' do
      expect(Recommendation.top_phrases('')).to eq([])
    end

    it 'caps at the limit kwarg' do
      text = 'Jannik Sinner. Carlos Alcaraz. Novak Djokovic. Roger Federer. Rafael Nadal.'
      expect(Recommendation.top_phrases(text, limit: 3).length).to eq(3)
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

      ranked = Recommendation.for_article(1, target, limit: 2).map { |r| r['title'] }
      # The two strong ruby/rails matches outrank the language-only JS post.
      expect(ranked).to contain_exactly('More Ruby tips', 'Database tips')
    end

    it 'excludes the target article from its own recommendations' do
      target = insert('a' * 12, 'Self', 'kubernetes networking is hard. kubernetes scaling is harder.')
      insert('b' * 12, 'Other', 'kubernetes pods and services explained.')

      ids = Recommendation.for_article(1, target).map { |r| r['id'] }
      expect(ids).not_to include(target['id'])
    end

    it 'returns [] when the article has too little content to extract keywords from' do
      target = insert('a' * 12, 'Empty', '')
      expect(Recommendation.for_article(1, target)).to eq([])
    end

    it 'returns [] when no other article shares any keyword' do
      target = insert('a' * 12, 'Lonely',
                      'thisisanunusualwordsequence quintessentialdiagonalpurpleflamingosparklingnonsense')
      insert('b' * 12, 'Unrelated', 'a completely different topic about cooking and recipes.')
      expect(Recommendation.for_article(1, target)).to eq([])
    end

    it 'honours the limit kwarg' do
      target = insert('a' * 12, 'T', 'kubernetes scaling is hard kubernetes is fun')
      6.times do |i|
        insert("b#{i}".ljust(12, '0'), "K post #{i}", 'kubernetes pods replicas autoscaling.')
      end
      expect(Recommendation.for_article(1, target, limit: 3).length).to eq(3)
    end

    it 'returns [] (no raise) on a nil article' do
      expect(Recommendation.for_article(1, nil)).to eq([])
    end
  end
end
