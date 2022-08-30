# frozen_string_literal: true

require 'sinatra/base'
require 'rest-client'
require_relative 'days_method'

module Sinatra
  # Helper functions to test status of file on S3 storage
  # used in app methods
  module S3Helpers
    def s3_hostname
      request.env['HTTP_X_FORWARDED_HOST'] || request.env['HTTP_HOST']
    end

    def s3_server
      bucket = settings.tenant_api.default_bucket(s3_hostname)
      if bucket&.length&.positive?
        # bucket was set using subdomain
        if ENV['S3_SERVER'].include?('https://')
          "https://#{bucket}.#{ENV['S3_SERVER'].gsub(%r{https://}, '')}"
        else
          "http://#{bucket}.#{ENV['S3_SERVER'].gsub(%r{http://}, '')}"
        end
      else
        ENV['S3_SERVER'].to_s
      end
    end

    def s3_unsplat(params_splat)
      s3_arguments = params_splat[0].split('/')

      # we use s3 hostname to get bucket for when path_style:false is used
      bucket = settings.tenant_api.default_bucket(s3_hostname)
      if bucket&.length&.positive?
        # bucket was set using subdomain
        file_hash = params_splat[0].gsub('[', '%5B').gsub(']', '%5D')
        hostname = s3_hostname.sub("#{bucket}.", '')
      elsif s3_arguments.length >= 2
        # bucket needs to be given in our path
        bucket = CGI.escape(params_splat[0].split('/')[0])
        file_hash = params_splat[0].split('/')[1..-1].join('/').gsub('[', '%5B').gsub(']', '%5D')
        hostname = s3_hostname
      end

      puts ">>> DEBUG s3 unsplat bucket=#{bucket} path=#{file_hash} and host=#{hostname} querystr=#{request.query_string}"

      halt 403, "Invalid bucket '#{bucket}'" unless bucket&.length&.positive?
      [hostname, bucket, file_hash]
    end

    # used to copy signed s3 headers from original request to pre-flight
    def copy_signed_headers(auth_token)
      headers = {
        'Authorization': auth_token
      }

      begin
        signed_headers = auth_token.split('SignedHeaders=')[1].split(',')[0].split(';')
      rescue StandardError
        signed_headers = []
      end

      signed_headers.each do |header|
        headers[header] = request.env["HTTP_#{header.upcase.tr('-', '_')}"]
      end

      headers['host'] = s3_hostname
      # rack has different handling for content-type and for content-lenght the HTTP_ is not used here
      headers['content-type'] = request.env['CONTENT_TYPE']
      headers
    end

    def mh_object_lookup(bucket, file_hash)
      # try cache first then extra mh lookup
      # object_cache_lookup = redis_get("#{bucket}/#{file_hash}")
      # object_id = if object_cache_lookup
      #              object_cache_lookup['object_id']
      #            else

      #            end

      # object_id
      settings.mh_api.lookup_s3_path(bucket, file_hash)
    end

    def status_request(_s3_token, s3_path)
      ongoing_restore = false
      restore_headers = {}
      # headers = copy_signed_headers(s3_token)

      _s3host, bucket, file_hash = s3_unsplat(s3_path)
      export_result = redis_get("#{bucket}/#{file_hash}")

      # if we have it in redis, we check the status of restore
      if export_result
        ongoing_restore = true
        export_result = JSON.parse(export_result) if export_result.instance_of?(String)
        status = 'in progress'
        status = export_result['status'] if export_result['status']
        status = export_result[:status] if export_result[:status]

        case status
        when 'completed'
          # right now we still need to move s3 file here
          ongoing_restore = true # worker still needs to move the file!
        when 'in_progress'
          ongoing_restore = true
        when 'failed'
          ongoing_restore = false # export failed so ongoing restore is not true anymore
        when 'restored' # we'll set this ourselves in export worker
          ongoing_restore = false # worker has copied file to new name
        end

      else # file not in S3 and not found to be restoring on redis cache
        # this will happen when we do a head request on some file that is in mh
        # but no restore call was done. and it was never uploaded with a 'put'
        # object_id = nil
        object_id = mh_object_lookup(bucket, file_hash)
        puts "HEAD >>> mh_object_lookup( #{bucket}, #{file_hash} ) -> object_id=#{object_id}"
        halt 404, 'File not found' if object_id.empty?
      end

      expiry_ts = Time.new + 14.days

      {
        ongoing_restore: ongoing_restore,
        status_headers: restore_headers, # headers contain content-length if s3_key_found
        expiry_date: expiry_ts.strftime('%a, %-d %B %Y %H:%M:%S GMT').to_s
      }
    end
  end
end
