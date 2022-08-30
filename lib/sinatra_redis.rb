# frozen_string_literal: true

require 'uri'
require 'redis'

# minimal module to use redis in sinatra
module Sinatra
  # have redis.get, redis.set available in sinatra methods for app.rb
  module RedisHelper
    def redis
      settings.redis
    end

    # redis helpers for get/set
    # these catch connection errors and have auto expire
    # on set keys with configurable REDIS_EXPIRE env var.
    def redis_get(key)
      redis.get(key)
    rescue ::Redis::CannotConnectError
      puts('Warning: in redis_get redis-server connect error!')
    end

    def redis_set(key, value)
      redis.set(key, value)
      redis.expire(key, ENV['REDIS_EXPIRE'].to_i || 900) # expire every 15 minutes
    rescue ::Redis::CannotConnectError
      puts('Warning: in redis_set redis-server connect error!')
    end
  end

  # have register redis available in sinatra app
  module Redis
    def redis=(url)
      @redis = nil
      set :redis_url, url
      redis
    end

    def redis
      @redis ||= begin
        url = URI(redis_url)

        base_settings = {
          host: url.host,
          port: url.port,
          # db is integer 0..16
          db: url.path[1..-1].to_i,
          password: url.password
        }

        ::Redis.new(
          base_settings.merge(
            redis_settings
          )
        )
      end
    end

    def self.registered(app)
      app.set :redis_url, ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0'
      app.set :redis_settings, {}
      app.helpers RedisHelper
    end
  end

  register Redis
end
