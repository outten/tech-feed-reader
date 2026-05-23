require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/support_messages_store'

# STUFF #62 — public /contact form + admin queue.
RSpec.describe 'Contact form + admin queue (STUFF #62)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'auth registration' do
    it 'registers /contact as a public path' do
      expect(Auth::PUBLIC_PATHS).to include('/contact')
    end
  end

  describe 'GET /contact' do
    it 'renders the form with the honeypot field present' do
      get '/contact'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('action="/contact"')
      expect(last_response.body).to include('name="website"')
      expect(last_response.body).to include('name="body"')
      expect(last_response.body).to include('name="subject"')
      expect(last_response.body).to include('name="reply_to"')
    end

    it 'shows the success notice when ?sent=1' do
      get '/contact?sent=1'
      expect(last_response.body).to include('your message is in the queue')
    end
  end

  describe 'POST /contact' do
    it 'stores a submission and redirects to /contact?sent=1' do
      expect {
        post '/contact', { body: 'Hello, this is a test.', subject: 'Hi', reply_to: 'me@example.com' }
      }.to change { SupportMessagesStore.list.length }.by(1)
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/contact?sent=1')

      msg = SupportMessagesStore.list.first
      expect(msg['body']).to eq('Hello, this is a test.')
      expect(msg['subject']).to eq('Hi')
      expect(msg['reply_to']).to eq('me@example.com')
      expect(msg['status']).to eq('new')
    end

    it 'attaches user_id when submitter is signed in' do
      post '/contact', { body: 'signed-in message' }
      msg = SupportMessagesStore.list.first
      # Default test user is id=1 (per spec_helper auto-signin).
      expect(msg['user_id'].to_i).to eq(1)
    end

    it 'rejects an empty body with 400 + the same form' do
      post '/contact', { body: '   ' }
      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Message is required.')
    end

    it 'silently accepts and discards honeypot-triggered submissions' do
      expect {
        post '/contact', { body: 'spam', website: 'http://spam.example.com' }
      }.not_to change { SupportMessagesStore.list.length }
      # Looks like success to the bot.
      expect(last_response.headers['Location']).to end_with('/contact?sent=1')
    end

    it 'trims subject + reply_to to their maxes' do
      long = 'a' * 1000
      post '/contact', { body: 'x', subject: long, reply_to: long }
      msg = SupportMessagesStore.list.first
      expect(msg['subject'].length).to eq(SupportMessagesStore::SUBJECT_MAX)
      expect(msg['reply_to'].length).to eq(SupportMessagesStore::REPLY_TO_MAX)
    end

    it 'stores nil for blank optional fields' do
      post '/contact', { body: 'body only' }
      msg = SupportMessagesStore.list.first
      expect(msg['subject']).to be_nil
      expect(msg['reply_to']).to be_nil
    end
  end

  describe 'GET /admin/support' do
    before do
      SupportMessagesStore.create!(user_id: nil, subject: 'anon msg', body: 'body 1', reply_to: nil)
      SupportMessagesStore.create!(user_id: 1,   subject: nil,        body: 'body 2', reply_to: 'reply@example.com')
    end

    it 'lists messages newest-first' do
      get '/admin/support'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('body 1')
      expect(last_response.body).to include('body 2')
      expect(last_response.body).to include('Support messages')
    end

    it 'filters by status when ?status= is set' do
      msg = SupportMessagesStore.list.first
      SupportMessagesStore.update!(msg['id'], status: 'reviewed')
      get '/admin/support?status=new'
      expect(last_response.body).not_to include(msg['body'])
    end
  end

  describe 'POST /admin/support/:id/update' do
    let(:msg) {
      SupportMessagesStore.create!(user_id: nil, subject: nil, body: 'pending', reply_to: nil)
    }

    it 'updates status + admin_note' do
      post "/admin/support/#{msg['id']}/update", { status: 'responded', admin_note: 'emailed back' }
      expect(last_response.status).to eq(302)

      updated = SupportMessagesStore.find(msg['id'])
      expect(updated['status']).to eq('responded')
      expect(updated['admin_note']).to eq('emailed back')
    end

    it '404s on an unknown id' do
      post '/admin/support/999999/update', { status: 'reviewed' }
      expect(last_response.status).to eq(404)
    end
  end
end
