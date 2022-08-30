# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/custom_logger'
require 'logger'
require 'json'
require 'bunny'

require './lib/sinatra_redis'
require './lib/mediahaven_api'
require './lib/tenant_api'
require './lib/s3_helpers'

require 'redis'
require 'sidekiq'
require 'sidekiq/api'
require 'sidekiq/web'
require 'connection_pool'
require_relative 'workers/export_status_worker'

# main sinatra application
class S3ProxyApp < Sinatra::Base
  helpers Sinatra::CustomLogger
  helpers Sinatra::S3Helpers
  register Sinatra::Redis

  configure :production, :development, :test do
    # for docker use stdout logger
    logger = Logger.new($stdout) if production?
    logger = Logger.new(File.open("#{root}/log/#{environment}.log", 'a')) if development?
    logger.level = Logger::DEBUG if development?
    set :logger, logger

    mh_api = MediahavenApi.new
    set :mh_api, mh_api

    # rabbit mq client
    rabbit = Bunny.new # amqp://guest:guest@localhost:5672
    set :rabbit_conn, rabbit

    # tenant domains
    tenant_api = TenantApi.new
    set :tenant_api, tenant_api

    # sidekiq workers
    workers = Sidekiq::Workers.new
    set :workers, workers

    # have redis also available
    set :redis_db, redis
  end

  # Root route show usage page with S3 and curl examples
  get '/' do
    content_type :html
    erb :index
  end

  # Clear redis cache route
  post '/clear_redis' do
    begin
      redis.flushdb
      @redis_stats = { Warning: 'Redis cache cleared' }
    rescue Redis::CannotConnectError
      @redis_stats = { Warning: "Can't connect to redis-server" }
    end
    erb :redis_stats
  end

  # Status of redis cache (shows redis usage stats)
  get '/redis_stats' do
    begin
      @redis_stats = redis.info
    rescue Redis::CannotConnectError
      @redis_stats = { Warning: "Can't connect to redis-server" }
    end
    erb :redis_stats
  end

  # Health call for OpenShift pod.
  get '/health' do
    content_type :json
    begin
      _redis_stats = redis.info
    rescue StandardError => e
      errors = "uncaught #{e} exception while handling connection: #{e.message}"
      halt 500, { 'Content-Type' => 'application/json' }, { message: errors }.to_json
    end

    return { message: 'redis and connection successfull' }.to_json
  end

  # S3 HEAD/status proxy also returns file size along with status for a restore request
  head '/*' do
    # logic change in case of 200 the caringo swarm returns response
    # all others mean its busy restoring or still on tape
    s3_auth_token = request.env['HTTP_AUTHORIZATION']
    status_response = status_request(s3_auth_token, params[:splat])
    ongoing_restore = status_response[:ongoing_restore]
    expiry_date = status_response[:expiry_date]

    headers['Content-Length'] = status_response[:status_headers][:content_length]
    # the actual header we want is x-amz-restore. But we target an nginx rewrite
    # because the caringo swarm puts this on meta for other files once restored
    headers['x-amz-storage-class'] = 'GLACIER'
    headers['x-amz-meta-amz-restore'] = if ongoing_restore
                                          "ongoing-request=\"#{ongoing_restore}\""
                                        else
                                          "ongoing-request=\"#{ongoing_restore}\", expiry-date=\"#{expiry_date}\""
                                        end
  end

  # S3 GET proxy
  # 404 : file not found
  # 403 : file is archived (found in mediahaven but not on s3 disk)
  #       can be restored using restore call below
  # 200 : ok file is present (this is handled by caringo now)
  # https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html
  # https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html#RESTObjectGET-responses-examples
  get '/*' do
    s3_auth_token = request.env['HTTP_AUTHORIZATION']
    s3host, bucket, file_hash = s3_unsplat(params[:splat])
    logger.info ">>> GET host=#{s3host} bucket=#{bucket}, file=#{file_hash}, token=#{s3_auth_token}"

    # here we know it was not on Caringo. Check redis (for restoring) then check mediahaven (archived)
    object_lookup = redis_get("#{bucket}/#{file_hash}")
    if object_lookup
      object_id = object_lookup['object_id']
      # archived response like amazon glacier
      halt 403, "<Error><Code>InvalidObjectState</Code><Message>File archived to tape</Message><ObjectId>#{object_id}</ObjectId></Error>"
    else
      # before returning 404, first also check media haven metadata using path and retrieve umid.
      mh_object = settings.mh_api.lookup_s3_path(bucket, file_hash)
      puts mh_object
      if mh_object.empty?
        # if also not found on media-haven then give back this 404 error:
        logger.info '404 error'
        halt 404, 'File not found'
      else
        halt 403, "<Error><Code>InvalidObjectState</Code><Message>File archived to tape</Message><ObjectId>#{mh_object['media_id']}</ObjectId></Error>"
      end
    end

    logger.info '>>> Prefetch GET 200 OK doing Redirect to S3 SERVER...'

    # proxy pass to Caringo/Swarm S3
    headers['Host'] = s3host
    headers['X-Accel-Redirect'] = '@s3store'
    headers['X-Accel-Buffering'] = 'no'
  end

  # S3 POST for multipart upload and restore requests
  post '/*' do
    s3host, bucket, file_hash = s3_unsplat(params[:splat])
    if params.key? 'restore' # we do a restore call here
      logger.info "POST restore bucket=#{bucket} file=#{file_hash}"

      halt 200 if settings.tenant_api.exists?(s3host, bucket, file_hash)
      # TODO: extend further ti onclude s3domain in query
      restore_object = mh_object_lookup(bucket, file_hash)

      # file not found on media haven, abort
      halt 404, 'File does not exist' if restore_object.empty?
      #
      # TODO: extend further if we find that a restore is already running then skip this here!
      # Temp hack
      halt 409, 'already running' if redis.get("#{bucket}/#{file_hash}")

      # right now we can call our worker with an object_id and do both
      # creating export + polling here
      puts "Creating export worker with object=#{restore_object}"
      ExportStatusWorker.perform_async(restore_object)

      halt 202
    else # Not implemented: we only accept restore requests
      halt 501
    end
  end

  # are now deprecated / handled by Caringo
  ## S3 PUT proxy
  # put '/*' do
  #  s3host, bucket, file_hash = s3_unsplat(params[:splat])
  #  logger.info "PUT host=#{s3host} bucket=#{bucket}, file=#{file_hash}"

  #  # proxy pass to S3 server with x-accel-redirect header
  #  # headers['Content-Disposition'] = ''
  #  headers['Host'] = s3host
  #  headers['X-Accel-Redirect'] = '@s3store'
  #  headers['X-Accel-Buffering'] = 'no'
  #  headers['User-Agent'] = request.env['HTTP_USER_AGENT']
  # end

  ## S3 DELETE proxy
  # delete '/*' do
  #  s3host, bucket, file_hash = s3_unsplat(params[:splat])
  #  logger.info "DELETE host=#{s3host} bucket=#{bucket}, file=#{file_hash}"

  #  headers['Host'] = s3host
  #  headers['X-Accel-Redirect'] = '@s3store'
  #  headers['X-Accel-Buffering'] = 'no'
  #  headers['User-Agent'] = request.env['HTTP_USER_AGENT']
  # end
end
