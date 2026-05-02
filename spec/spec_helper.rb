require 'rspec'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

RSpec.configure do |c|
  c.color = true
  c.formatter = :documentation
end
