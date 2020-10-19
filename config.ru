# frozen_string_literal: true

require './app'
require 'sidekiq'
require 'sidekiq/web'

Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0', network_timeout: 3 }
  # config.on(:startup) do
  #  $redis_db = config.redis
  # end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0', network_timeout: 3 }
end

# if ENV['RACK_ENV'].to_s.eql?('development')
#  # allow sidekiq pages to be shown also during development
#  puts 'Running in dev mode, use /sidekiq to view workers'
#  run Rack::URLMap.new('/sidekiq_workers': Sidekiq::Web, '/': S3ProxyApp)
# else
# all paths map to s3proxy that way a bucket name of sidekiq will also keep on working
# and we don't expose sidekiq admin pages here
puts 'Server is in production mode'
run S3ProxyApp
# end
