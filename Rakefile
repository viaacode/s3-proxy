# frozen_string_literal: true

# Rakefile
# require 'sinatra/activerecord/rake'
require './app'
require 'rake'
require 'rake/testtask'

# set to nginx server that proxy_passes to
# both app and minio server, also set some
# env variables used for Tenant api (file copy)
# and polling config and export location id for mediahaven.
ENV['S3_SERVER'] = 'http://localhost:9999'
ENV['TENANT_API'] = 'http://s3-testing.be:888'
ENV['MEDIAHAVEN_SWARM'] = 'http://s3-testing.be:888'
ENV['EXPORT_LOCATION_ID'] = '1188'
ENV['STATUS_MAX_POLL_COUNT'] = '30'
ENV['STATUS_POLL_INTERVAL'] = '3'

Rake::TestTask.new do |t|
  t.pattern = 'test/**/*_test.rb'
  t.warning = false
end

task default: :test
