require 'rspec'
RSpec::Mocks.setup(Object)

require 'pipes'

Pipes.namespace = 'test'

begin
  Redis.current.ping
rescue
  puts 'Please start Redis before running the specs.'
  exit
end