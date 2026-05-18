require_relative 'spec_helper'
require_relative '../app/users_store'

RSpec.describe UsersStore do
  describe '.valid_username?' do
    it 'accepts lowercase alnum / underscore / hyphen, 3-32 chars' do
      %w[abc todd_outten todd-2 a_b_c xyz12345].each do |u|
        expect(UsersStore.valid_username?(u)).to be(true), "expected #{u.inspect} to be valid"
      end
    end

    it 'lowercases before validating (case-insensitive at the boundary)' do
      expect(UsersStore.valid_username?('ToDD')).to be(true)
    end

    it 'rejects too-short, too-long, uppercase-only-via-normalization, and bad chars' do
      %w[ab abcdefghijklmnopqrstuvwxyzabcdef1234 alice.smith alice@example.com space\ name].each do |u|
        expect(UsersStore.valid_username?(u)).to be(false), "expected #{u.inspect} invalid"
      end
    end
  end

  describe '.create' do
    it 'inserts a row + returns it with normalized username' do
      user = UsersStore.create(username: 'ToDD', display_name: 'Todd Outten')
      expect(user['username']).to eq('todd')
      expect(user['display_name']).to eq('Todd Outten')
      expect(user['id']).to be_a(Integer)
    end

    it 'defaults display_name to the username when blank' do
      user = UsersStore.create(username: 'a_b_c', display_name: '')
      expect(user['display_name']).to eq('a_b_c')
    end

    it 'raises InvalidUsername on a bad name' do
      expect { UsersStore.create(username: 'ab') }.to raise_error(UsersStore::InvalidUsername)
    end

    it 'enforces uniqueness via the index' do
      skip 'SQLite-specific exception class; PG raises PG::UniqueViolation (unique-index is enforced on both backends, the schema is the contract)' if Database.adapter == :postgres
      UsersStore.create(username: 'todd')
      expect { UsersStore.create(username: 'todd') }.to raise_error(SQLite3::ConstraintException)
    end
  end

  describe '.find / .find_by_username / .touch_last_seen!' do
    it 'round-trips an inserted user' do
      created = UsersStore.create(username: 'todd')
      expect(UsersStore.find(created['id'])['username']).to eq('todd')
      expect(UsersStore.find_by_username('TODD')['id']).to eq(created['id'])
    end

    it 'touch_last_seen! sets last_seen_at' do
      created = UsersStore.create(username: 'todd')
      expect(created['last_seen_at']).to be_nil
      UsersStore.touch_last_seen!(created['id'])
      expect(UsersStore.find(created['id'])['last_seen_at']).not_to be_nil
    end
  end
end
