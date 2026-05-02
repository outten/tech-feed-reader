require_relative 'spec_helper'
require_relative '../app/database'

# Database is a singleton — each spec resets the connection so the
# in-memory DB starts empty.
RSpec.describe Database do
  before(:each) { Database.reset! }
  after(:each)  { Database.reset! }

  describe '.migrate!' do
    it 'applies pending migrations and records their versions' do
      applied = Database.migrate!
      expect(applied).to be > 0

      versions = Database.connection
        .execute('SELECT version FROM schema_migrations')
        .map { |r| r['version'] }
      expect(versions).to include('001_init')
    end

    it 'is idempotent — a second call applies zero migrations' do
      Database.migrate!
      expect(Database.migrate!).to eq(0)
    end
  end

  describe 'schema' do
    before(:each) { Database.migrate! }

    it 'creates every table the v1 stores need' do
      tables = Database.connection
        .execute("SELECT name FROM sqlite_master WHERE type='table'")
        .map { |r| r['name'] }

      %w[
        schema_migrations feeds articles read_state
        tags article_tags summaries
      ].each do |t|
        expect(tables).to include(t)
      end
    end

    it 'enforces feed_id foreign key on articles (cascade)' do
      db = Database.connection
      expect {
        db.execute(
          'INSERT INTO articles(uid, feed_id, title, url) VALUES (?, ?, ?, ?)',
          ['abc123def456', 999, 'Orphan', 'https://example.com/post']
        )
      }.to raise_error(SQLite3::ConstraintException, /FOREIGN KEY/)
    end

    it 'cascades article deletion to read_state and summaries' do
      db = Database.connection
      db.execute('INSERT INTO feeds(url, title) VALUES (?, ?)',
                 ['https://example.com/feed', 'Test'])
      feed_id = db.last_insert_row_id

      db.execute(<<~SQL, ['abc123def456', feed_id, 'Hi', 'https://example.com/post'])
        INSERT INTO articles(uid, feed_id, title, url) VALUES (?, ?, ?, ?)
      SQL
      article_id = db.last_insert_row_id

      db.execute('INSERT INTO read_state(article_id, read) VALUES (?, 1)', [article_id])
      db.execute(<<~SQL, [article_id, 'short'])
        INSERT INTO summaries(article_id, extractive) VALUES (?, ?)
      SQL

      db.execute('DELETE FROM feeds WHERE id = ?', [feed_id])

      expect(db.execute('SELECT COUNT(*) AS c FROM articles').first['c']).to eq(0)
      expect(db.execute('SELECT COUNT(*) AS c FROM read_state').first['c']).to eq(0)
      expect(db.execute('SELECT COUNT(*) AS c FROM summaries').first['c']).to eq(0)
    end

    it 'rejects invalid match_kind on tags via CHECK constraint' do
      db = Database.connection
      expect {
        db.execute('INSERT INTO tags(name, match_kind, match_value) VALUES (?, ?, ?)',
                   ['x', 'bogus', 'whatever'])
      }.to raise_error(SQLite3::ConstraintException, /CHECK/)
    end
  end

  describe 'FTS5 sync' do
    before(:each) do
      Database.migrate!
      db = Database.connection
      db.execute('INSERT INTO feeds(url, title) VALUES (?, ?)',
                 ['https://example.com/feed', 'Test'])
      @feed_id = db.last_insert_row_id
    end

    def insert_article(uid:, title:, content_text:)
      db = Database.connection
      db.execute(<<~SQL, [uid, @feed_id, title, "https://example.com/#{uid}", content_text])
        INSERT INTO articles(uid, feed_id, title, url, content_text)
        VALUES (?, ?, ?, ?, ?)
      SQL
      db.last_insert_row_id
    end

    it 'INSERT trigger indexes the new article' do
      insert_article(uid: 'a' * 12, title: 'Hello world', content_text: 'Lorem ipsum dolor.')

      hits = Database.connection
        .execute("SELECT title FROM articles_fts WHERE articles_fts MATCH 'lorem'")
        .map { |r| r['title'] }
      expect(hits).to eq(['Hello world'])
    end

    it 'UPDATE trigger refreshes the index' do
      id = insert_article(uid: 'b' * 12, title: 'Initial', content_text: 'first body')
      Database.connection.execute(
        'UPDATE articles SET title = ?, content_text = ? WHERE id = ?',
        ['Revised', 'second body', id]
      )

      old_hits = Database.connection
        .execute("SELECT title FROM articles_fts WHERE articles_fts MATCH 'first'")
        .map { |r| r['title'] }
      new_hits = Database.connection
        .execute("SELECT title FROM articles_fts WHERE articles_fts MATCH 'second'")
        .map { |r| r['title'] }

      expect(old_hits).to be_empty
      expect(new_hits).to eq(['Revised'])
    end

    it 'DELETE trigger removes the article from the index' do
      id = insert_article(uid: 'c' * 12, title: 'Doomed', content_text: 'temporary text')
      Database.connection.execute('DELETE FROM articles WHERE id = ?', [id])

      hits = Database.connection
        .execute("SELECT title FROM articles_fts WHERE articles_fts MATCH 'temporary'")
        .map { |r| r['title'] }
      expect(hits).to be_empty
    end
  end
end
