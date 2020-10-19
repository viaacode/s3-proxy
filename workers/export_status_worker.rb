# frozen_string_literal: true

# require 'sidekiq'
# worker to asynchronously keep track of the export status
class ExportStatusWorker
  include Sidekiq::Worker

  # allow writing to our redis instance from within worker
  def redis
    @redis ||= begin
      url = URI(ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0')

      base_settings = {
        host: url.host,
        port: url.port,
        # db is integer 0..16 givin inside REDIS_URL
        db: url.path[1..-1].to_i,
        password: url.password
      }

      ::Redis.new(
        base_settings.merge(
          {}
        )
      )
    end
  end

  # values for qas & prd once we have tested initial version with smaller intervals
  POLL_INTERVAL_SECONDS = (ENV['STATUS_POLL_INTERVAL'].to_i || 60)  # set to 60 seconds interval between each call to MAM in prd/qas
  POLL_COUNT = (ENV['STATUS_MAX_POLL_COUNT'].to_i || 60 * 24 * 2)   # 2 days if poll interval=60

  def start_restore(mh_api, restore_object)
    bucket = restore_object['bucket']
    file_hash = restore_object['file_hash']

    # first check if a previous restore call was not done for this file
    # restore again by looking in redis cache and on S3 caringo
    # if so-> set export result status to 'already restored' that way it will exit immediately...
    prevrun = redis.get("#{bucket}/#{file_hash}")
    if prevrun
      export_already_started = { 'status': 'already running', 'progress': 1 }.to_json.to_s
      return export_already_started
    end

    # signal immediately that we're starting an export on this so thats
    # first status request sees ongoing-restore == true!
    export_starting = {
      'status': 'starting',
      'progress': '0',
      'object_id': restore_object['media_id']
    }
    redis.set("#{bucket}/#{file_hash}", export_starting.to_json)
    redis.expire("#{bucket}/#{file_hash}", 90) # 90 seconds so that when next calls timeout the cache will be cleared after 1.5 minute

    puts "ExportStatusWorker >>> calling mediahaven export with object_id=#{restore_object['media_id']}..."
    begin
      export_result = mh_api.export_to_path(restore_object['media_id'],
                                            ENV['EXPORT_LOCATION_ID'].to_i,
                                            bucket,
                                            restore_object['tempkey'],
                                            'restoring for s3proxy')
      export_result['object_id'] = restore_object['media_id']
      # export_result['owner'] = restore_object['owner']
      redis.set("#{bucket}/#{file_hash}", export_result)
      redis.expire("#{bucket}/#{file_hash}", 90) # after 15min normally (for debug set to 1.5) mins allow refetching to mh again for status
      puts "ExportStatusWorker >>> redis SET key: (#{bucket}/#{file_hash} -> #{export_result}"
    rescue RestClient::Unauthorized
      puts 'ExportStatusWorker >>> ERROR: status worker needs to die, unauthorised export result'
      export_result = { 'status': 'failure, mediahaven unauthorized error' }
    end

    export_result
  end

  def export_failed(restore_object, export_status)
    bucket = restore_object['bucket']
    file_hash = restore_object['file_hash']

    progress = 0
    progress = export_status['progress'] if export_status && export_status['progress']
    restore_failed = {
      'status': 'failed',
      'progress': progress,
      'object_id': restore_object['media_id']
    }

    puts "ExportStatusWorker >>> WARNING: worker process for object #{restore_object} terminated."
    redis.set("#{bucket}/#{file_hash}", restore_failed.to_json)
    redis.expire("#{bucket}/#{file_hash}", 10) # clear after 10 seconds, so retry is possible
    puts "ExportStatusWorker >>> redis cache clearing in 10 seconds for failed object_id=#{restore_object['media_id']} bucket=#{bucket} file_hash=#{file_hash}"
  end

  def wait_for_restore(mh_api, bucket, file_hash, export_id)
    # polling_minutes is there to make zombie worker die after a few days
    polling_minutes = 0 # later we can set this to some really high value to make a worker die in case something is wrong
    export_status = {}

    # if export result was created, start polling and after 2 days just give up
    while polling_minutes < POLL_COUNT
      puts "ExportStatusWorker >>> Make mediahaven api call with id #{export_id} checking export status..."
      begin
        export_status = mh_api.export_status(export_id)
        puts "ExportStatusWorker >>> redis SET key: (#{bucket}/#{file_hash} -> #{export_status}"
        redis.set("#{bucket}/#{file_hash}", export_status.to_json)
        redis.expire("#{bucket}/#{file_hash}", 600) # expire after 10 mins of inactivity
      rescue SocketError
        puts "Socket error during mh request for export_id=#{export_id}"
      rescue RestClient::MethodNotAllowed
        puts "method not allowed in export_id=#{export_id}"
      rescue RestClient::Unauthorized
        puts "401: Unauthorized error in export status call for export_id=#{export_id}"
      end

      break if export_status && (export_status['status'] == 'failed')
      break if export_status && (export_status['status'] == 'completed' || export_status['progress'] == 100)

      sleep POLL_INTERVAL_SECONDS
      polling_minutes += 1
    end

    export_status
  end

  def perform(restore_object)
    # init media haven api inside the worker
    puts "ExportStatusWorker >>> restore_object=#{restore_object}"
    s3host = restore_object['s3host']
    bucket = restore_object['bucket']
    file_hash = restore_object['file_hash']
    restore_object['tempkey'] = "tmp__#{file_hash.tr('/', '')}"
    # initialize mediahaven api to do object id lookup
    mh_api = MediahavenApi.new

    # call mediahaven and start a new restore if necessary
    export_result = start_restore(mh_api, restore_object)
    if !export_result || (export_result['status'] != 'created')
      puts "ExportStatusWorker >>> Worker is exiting: status=#{export_result}"
      return # do a raise here if you instead want the job to retry...
    end

    # now poll the given export_id until export is finished
    export_id = export_result['exportId']
    export_status = wait_for_restore(mh_api, bucket, file_hash, export_id)

    # Move file into the correct bucket and file hash (as mediahaven restores it to a different name)
    if export_status['status'] == 'completed'
      begin
        tenant_api = TenantApi.new
        puts tenant_api.copy(restore_object) # copy file to correct destination name
        puts "ExportStatusWorker >>> Updating headers for #{restore_object}"
        # now signal following head requests that restore is finished by putting 'restored' in the status!
        file_is_restored_status = {
          'status': 'restored',
          'progress': export_status['progress'],
          'object_id': restore_object['media_id']
        }
        redis.set("#{bucket}/#{file_hash}", file_is_restored_status.to_json)
        redis.expire("#{bucket}/#{file_hash}", 300) # now during testing after few minutes
        # redis.expire("#{bucket}/#{file_hash}", 60 * 60 * 24 * 14) # expire after 14 days!
        puts 'ExportStatusWorker >>> file copied to destination (redis expiry now 5minutes, in future bump this to 14 days)'
        return
      rescue StandardError => err
        puts "ExportStatusWorker >>> ERROR: tenant_api.copy(#{s3host} #{restore_object} failed: #{err.message}"
      end

    end

    # if we reached here, something went wrong during copy, we signal with a failed status in redis
    export_failed(restore_object, export_status)
  end
end
