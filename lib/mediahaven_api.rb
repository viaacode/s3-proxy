# frozen_string_literal: true

require 'rest-client'
require 'json'
require_relative 'api_helpers'

# Class with api calls for Media Haven
# Accept: application/xml or Accept: application/json are supported
# we now do basic auth, later on possibly do oauth 2.
class MediahavenApi
  def initialize(
    api_server: (ENV['MEDIAHAVEN_API'] || 'https://media-api-tests.be'),
    api_user: (ENV['MEDIAHAVEN_USER'] || 'apiUser'),
    api_password: (ENV['MEDIAHAVEN_PASS'] || 'apiPass'),
    logger: StdOutLogger.new
  )
    @api_url = api_server.to_s
    @api_user = api_user.to_s
    @api_password = api_password.to_s
    @logger = logger
  end

  def url
    @api_url
  end

  # list mediahaven objects.
  # example value for search =
  # +(MediaObjectOwnerName:\#group\# AND
  # (MediaObjectoriginalFileName:*.wav OR MediaObjectoriginalFileName:*.mxf) AND
  # (MediaObjectType:video OR MediaObjectType:audio))
  def list_objects(search: '', offset: 0, limit: 25)
    qry = CGI.escape(search || '')
    get_proxy("/resources/media?q=#{qry}&startIndex=#{offset}&nrOfResults=#{limit}")
  end

  # get object by id from mediahaven
  def get_object(object_id)
    get_proxy("/resources/media/#{object_id}")
  end

  # Given a valid bucket+filename give back the associated mediaObjectId that can be used to restore
  def lookup_s3_path(bucket, file_hash)
    object = {}
    begin
      # we exclude video fragments so that we don't get back multiple results if fragments have been added
      search_matches = list_objects(search: "+(s3_object_key:\"#{file_hash}\") +(s3_bucket:\"#{bucket}\") -(Type:videofragment)")
      if search_matches['totalNrOfResults'].positive?
        fragment = search_matches['mediaDataList'].first
        puts 'fragmentID:', fragment['fragmentId']
        puts 'mdProperties:', fragment['mdProperties']
        object = {
          'media_id': fragment['fragmentId'],
          'bucket': fragment['mdProperties'].find { |x| x['attribute'] == 's3_bucket' }['value'],
          'domain': fragment['mdProperties'].find { |x| x['attribute'] == 's3_domain' }['value'],
          'owner': fragment['mdProperties'].find { |x| x['attribute'] == 's3_object_owner' }['value'],
          'file_hash': file_hash,
          'md5sum': fragment['mdProperties'].find { |x| x['attribute'] == 'md5_viaa' }['value']
        }
      end
    rescue RestClient::Unauthorized
      puts "401 Error while trying mh_api.lookup_s3_path bucket=#{bucket} and file=#{file_hash} (user=#{@api_user} pass=#{@api_pass})"
    end
    puts object
    object
  end

  def export_locations
    get_proxy('/resources/exportlocations')
  end

  def export_location(location_id)
    get_proxy("/resources/exportlocations/#{location_id}")
  end

  def default_export_location
    export_location('default')
  end

  # export object from tape to storage specified by default location
  # basically this starts the export and then gives back an exportId and status
  # which can be polled with export_status calls
  # this uses the default_export_location
  def export_to_default(object_id, reason)
    begin
      response = RestClient::Request.execute(
        method: :post,
        multipart: true,
        headers: {
          content_type: :json
        },
        data: { exportReason: reason },
        user: @api_user,
        password: @api_password,
        url: "#{@api_url}/resources/media/#{object_id}/export",
        verify_ssl: false
      )
      result = JSON.parse(response.body)[0]
    rescue RestClient::MethodNotAllowed
      result = { status: 'Not allowed' }
    rescue RestClient::BadRequest
      result = { status: 'Bad request' }
    rescue RestClient::Forbidden
      result = { status: 'Forbidden' }
    end

    result
  end

  # export given a specific export location_id
  def export_to_location(object_id, export_location_id, reason)
    begin
      response = RestClient::Request.execute(
        method: :post,
        multipart: true,
        headers: {
          content_type: :json
        },
        data: { exportReason: reason },
        user: @api_user,
        password: @api_password,
        verify_ssl: false,
        url: "#{@api_url}/resources/media/#{object_id}/export/#{export_location_id}"
      )
      result = JSON.parse(response.body)[0]
    rescue RestClient::MethodNotAllowed
      result = { status: 'Not allowed' }
    rescue RestClient::BadRequest
      result = { status: 'Bad request' }
    rescue RestClient::Forbidden
      result = { status: 'Forbidden' }
    end

    result
  end

  # export to a specified destination path and optionally filename
  # path should include bucket here also
  # we probably also need domain here somewhere too in future where vrt or another
  # tenant is allowed to make its own buckets (then bucket name + filename is not unique anymore
  # and the destination needs to be unique dom+bucket+filename will guarantee this)
  def export_to_path(fragment_id, export_location_id, dest_path, dest_filename, reason)
    begin
      export_data = {
        exports: [
          {
            fragmentId: fragment_id,
            filename: dest_filename
          }
        ],
        useOriginal: true,
        exportOptions: {
          exportLocationId: export_location_id
        },
        destinationPath: dest_path,
        exportReason: reason,
        combine: 'NONE'
      }

      response = RestClient::Request.execute(
        method: :post,
        multipart: false,
        headers: {
          content_type: :json
        },
        payload: export_data.to_json,
        user: @api_user,
        password: @api_password,
        verify_ssl: false,
        url: "#{@api_url}/resources/exports"
      )
      puts response.to_s
      result = JSON.parse(response.body)[0]
    rescue RestClient::MethodNotAllowed
      result = { status: 'Not allowed' }
    rescue RestClient::BadRequest
      result = { status: 'Bad request' }
    rescue RestClient::Forbidden
      result = { status: 'Forbidden' }
    end

    result
  end

  # export to 1188 on qas and some other id on production
  # we use EXPORT_ID as environment variable to adjust this
  def export(object_id, reason)
    export_to_location(object_id, ENV.fetch('EXPORT_LOCATION_ID', nil), reason)
  end

  # After an export or export_location we can check the restore status.
  # status can be one of following:
  #   created  : export job is successfully created
  #   waiting  : export job is waiting to be started
  #   in_progress  : export is in progress
  #   failed : export failed
  #   completed  : export is completed, downloadUrl is available
  #   cancelled  : export was cancelled by the user
  #   already_exists_at_dst  : file already exists at destination, export stopped
  def export_status(export_id)
    export_results = get_proxy("/resources/exports/#{export_id}")
    export_results[0]
  end

  # Generic GET request to mediahaven api.
  # example: api.get_proxy( '/resources/exportlocations/default' )
  def get_proxy(api_route)
    response = RestClient::Request.execute(
      method: :get,
      headers: {
        content_type: :json
      },
      user: @api_user,
      password: @api_password,
      verify_ssl: false,
      url: "#{@api_url}#{api_route}"
    )

    JSON.parse(response.body)
  end
end
