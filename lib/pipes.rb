module Pipes
  # Default options
  @redis   = $redis
  @resolve = true

  class << self
    attr_reader :redis
    attr_accessor :namespace, :resolve
  end

  def self.configure(*args, &block)
    yield self
  end

  # config.redis can be a string or a redis connection
  #   eg: config.redis = 'localhost:6379'
  #   or  config.redis = $MY_REDIS
  def self.redis=(redis)
    if redis.is_a? String
      host, port = redis.split(':')
      set_redis(Redis.new(host: host, port: port))
    else
      set_redis(redis)
    end
  end

  def self.stages(*args, &block)
    Abyss.configure(*args) do
      stages &block
    end
  end

  private

  def self.set_redis(redis)
    @redis        = redis
    Resque.redis  = redis
    Redis.current = redis
  end
end

require 'pipes/utils'
require 'pipes/stage_parser'
require 'pipes/store'
require 'pipes/runner'
require 'pipes/resque_hooks'