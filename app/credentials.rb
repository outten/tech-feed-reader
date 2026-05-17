require 'dotenv'

# Single source of truth for loading API credentials. Loads
# `.credentials` (canonical, primary) then `.env` (Dotenv default —
# honoured but not written to). Both are git-ignored.
#
# Also normalises Claude key naming. The user's `.credentials` file
# uses `CLAUDE_API_KEY` (the friendlier name), but the Anthropic Ruby
# SDK reads `ANTHROPIC_API_KEY` from the environment. We alias the
# former into the latter at load time so both naming conventions
# work — including for the Summarizer::Claude code path that's been
# checking ANTHROPIC_API_KEY since day one.
#
# Required by app/main.rb (web) and app/sidekiq_boot.rb (worker) so
# both processes have the key. Idempotent — `||=` won't clobber an
# already-set ANTHROPIC_API_KEY (e.g. from a CI secret).
module Credentials
  ROOT = File.expand_path('../..', __FILE__)

  module_function

  def load!
    # In test mode, leave ENV alone so a developer's local `.env`
    # (notably DATABASE_URL after Phase 5 / D-PG-2) doesn't quietly
    # point the suite at a real Postgres database. spec_helper.rb
    # opts into PG explicitly via TEST_DATABASE_URL — see comment
    # there. This matches the long-stated intent in spec_helper's
    # comment block ("Tests don't read .env").
    return if ENV['RACK_ENV'] == 'test'

    Dotenv.load(File.join(ROOT, '.credentials'))
    Dotenv.load(File.join(ROOT, '.env'))
    ENV['ANTHROPIC_API_KEY'] ||= ENV['CLAUDE_API_KEY'] if ENV['CLAUDE_API_KEY']
  end
end

Credentials.load!
