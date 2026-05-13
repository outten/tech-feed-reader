require_relative 'spec_helper'
require_relative '../app/users_store'
require_relative '../app/recovery_codes_store'

RSpec.describe RecoveryCodesStore do
  let(:user) { UsersStore.create(username: 'todd') }

  describe '.generate_plaintext' do
    it 'produces 5 groups of 4 base32 chars joined by hyphens' do
      code = RecoveryCodesStore.generate_plaintext
      expect(code).to match(/\A[A-Z2-9]{4}(?:-[A-Z2-9]{4}){4}\z/)
    end

    it 'returns a different code each call (random)' do
      seen = 50.times.map { RecoveryCodesStore.generate_plaintext }
      expect(seen.uniq.length).to eq(seen.length)
    end
  end

  describe '.mint_for!' do
    it 'mints 10 codes by default + persists their hashes' do
      codes = RecoveryCodesStore.mint_for!(user_id: user['id'])
      expect(codes.length).to eq(10)
      expect(RecoveryCodesStore.unconsumed_count_for(user['id'])).to eq(10)
    end

    it 'never stores plaintext' do
      codes = RecoveryCodesStore.mint_for!(user_id: user['id'])
      stored = Database.connection.execute('SELECT code_hash FROM recovery_codes')
      codes.each { |c| expect(stored.map { |r| r['code_hash'] }).not_to include(c) }
    end
  end

  describe '.consume!' do
    it 'returns the user_id on a valid first use' do
      codes = RecoveryCodesStore.mint_for!(user_id: user['id'])
      expect(RecoveryCodesStore.consume!(codes.first)).to eq(user['id'])
    end

    it 'returns nil on a code that was already used' do
      codes = RecoveryCodesStore.mint_for!(user_id: user['id'])
      RecoveryCodesStore.consume!(codes.first)
      expect(RecoveryCodesStore.consume!(codes.first)).to be_nil
    end

    it 'returns nil on garbage input' do
      expect(RecoveryCodesStore.consume!('not-a-real-code')).to be_nil
      expect(RecoveryCodesStore.consume!('')).to be_nil
    end

    it 'is forgiving of whitespace and case' do
      codes = RecoveryCodesStore.mint_for!(user_id: user['id'])
      sloppy = " #{codes.first.downcase} "
      expect(RecoveryCodesStore.consume!(sloppy)).to eq(user['id'])
    end

    it 'decrements unconsumed_count_for after each use' do
      RecoveryCodesStore.mint_for!(user_id: user['id'])
      codes = RecoveryCodesStore.mint_for!(user_id: user['id'])  # mint a second batch — total 20
      first_count = RecoveryCodesStore.unconsumed_count_for(user['id'])
      RecoveryCodesStore.consume!(codes.first)
      expect(RecoveryCodesStore.unconsumed_count_for(user['id'])).to eq(first_count - 1)
    end
  end
end
