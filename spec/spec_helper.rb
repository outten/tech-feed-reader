require 'rspec'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

require_relative '../app/database'

# Reset + re-migrate the in-memory DB before every example so each spec
# starts from a clean, schema-loaded slate. database_spec layers its own
# Database.reset! on top to test the migrator itself; that's compatible —
# resetting closes the (in-memory) connection, the test body then opens
# a fresh empty DB and exercises migrate! from scratch.
RSpec.configure do |c|
  c.color = true
  c.formatter = :documentation

  c.before(:each) do
    Database.reset!
    Database.migrate!
  end

  c.after(:each) do
    Database.reset!
  end
end
