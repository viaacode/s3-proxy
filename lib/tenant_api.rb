# frozen_string_literal: true

require 'rest-client'
require 'json'
require 'active_support/core_ext/hash'
require_relative 'api_helpers'

# Class with api calls to get tenant domains and default bucket names
class TenantApi
  def initialize(
                  api_server: (ENV['TENANT_API'] || 'Unconfigured TENANT_API setting missing!'),
                  api_user: (ENV['TENANT_USER'] || ''),
                  api_password: (ENV['TENANT_PASS'] || ''),
                  mh_swarm_url: (ENV['MEDIAHAVEN_SWARM'] || 'http://mediahaven.prd.do.viaa.be'),
                  logger: StdOutLogger.new
                )
    @api_url = api_server.to_s
    @api_user = api_user.to_s
    @api_password = api_password.to_s
    @mh_swarm_url = mh_swarm_url
    @tenants = [] # we cache our tenants after first fetch here
    logger.debug("TenantApi initialised on url=#{@api_url}.\n")
  end

  # Temporray hack: improve with backend configuration and integrate with copy
  # and other backend operations
  def exists?(s3host, bucket, file_hash)
    begin
      head = RestClient.head("#{@mh_swarm_url}/#{bucket}/#{file_hash}?domain=#{s3host}")
    rescue RestClient::NotFound
      return false
    end
    head.code < 400
  end

  # copy call used to move a file to a new position
  def copy(restore_object)
    copy_url = "#{@mh_swarm_url}/#{restore_object['bucket']}/#{restore_object['tempkey']}?domain=#{restore_object['domain']}&newname=#{restore_object['file_hash']}"
    expiry_ts = Time.new + 14.days
    puts "tenant api copy call: #{copy_url}"

    head = RestClient.head(copy_url)
    begin
      RestClient::Request.execute(
        method: :copy,
        headers: {
          content_type: head.headers[:content_type],
          x_amz_storage_class_meta: head.headers[:x_amz_storage_class_meta],
          # this turns into x-amz-meta-amz-restore and is then translated into x-amz-restore with nginx rewrite
          'x-amz-restore-meta': "ongoing-request=\"false\", expiry-date=\"#{expiry_ts.strftime('%a, %-d %B %Y %H:%M:%S GMT')}\"",
          'x-amz-md5sum-meta': restore_object['md5sum'],
          'X-Owner-Meta': restore_object['owner']
        },
        user: @api_user,
        password: @api_password,
        url: copy_url
      )
    rescue RestClient::MovedPermanently => err
      err.response.follow_redirection
    end
  end

  # delete call can be used for cleanup during smoke tests
  def delete_file(domain, bucket, file)
    delete_url = "#{@api_url}/#{bucket}/#{file}?domain=#{domain}"
    begin
      response = RestClient::Request.execute(
        method: :delete,
        headers: {
          content_type: 'video/mp4',
          'X-ACL-Meta': "F:U:#{@api_user},R:B:ALL",
          'x-viaa-meta-cpid': 'iOR-cpidstring'
        },
        user: @api_user,
        password: @api_password,
        url: delete_url
        # http_wire_trace: true
      )
      response.body
    rescue StandardError => e
      puts "e=#{e.inspect} #{e.response}"
    end
  end

  def search_objects(domain, bucket, mh_object_id)
    response = RestClient::Request.execute(
      method: :get,
      user: @api_user,
      password: @api_password,
      url: "#{@api_url}/#{bucket}/?format=xml&prefix=#{mh_object_id}&domain=#{domain}"
      # format=xml or format=json is now mandatory!
    )
    Hash.from_xml(response.body)
  end

  def search(s3_host_url, bucket, mh_object_id)
    domain = s3_host_url.split(':')[0] # strip port
    domain.sub!(bucket + '.', '') # only leave domain without bucket subdomain

    result = search_objects(domain, bucket, mh_object_id)
    if result&.dig('ListBucketResult')
      return result.dig('ListBucketResult').dig('Contents')[0].dig('Key') if result.dig('ListBucketResult').dig('Contents')&.class == Array

      return result.dig('ListBucketResult').dig('Contents').dig('Key')
    end
    false
  end

  # tenant_list gets an array of configured tenants example response:
  # [
  #   {
  #    "name":"or-testm","lastModified":"2019-03-25T15:20:33.996000Z",
  #    "owner":"admin@","contentMd5":"eaeafaewfaw==",
  #    "etag":"someetag"
  #   },
  #   ...
  # ]
  def tenant_list
    response = RestClient::Request.execute(
      method: :get,
      headers: {
        content_type: :json
      },
      user: @api_user,
      password: @api_password,
      url: "#{@api_url}/_admin/manage/tenants"
    )
    JSON.parse(response.body)
  rescue RestClient::Forbidden
    puts 'Warning: tenant_list got 403 Forbidden error. Skipping!'
    JSON.parse('[]')
  end

  # gets array of domains belonging to specific tenant_name example:
  # [
  #   {
  #     "name":"somedomain.be",
  #     "lastModified":"2019-03-25T14:32:38.816000Z",
  #     "owner":"test@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",
  #     "etag":"700a03b2c34998f3880982a20a031969"
  #   },
  #   ...
  # ]
  # examples of tenant names:
  # gateway    a default one
  def tenant_domains(tenant)
    response = RestClient::Request.execute(
      method: :get,
      headers: {
        content_type: :json
      },
      user: @api_user, # this was with nil value and worked on previous Caringo but now gives 401 errors!
      password: @api_password,
      url: "#{@api_url}/_admin/manage/tenants/#{tenant}/domains"
    )
    JSON.parse(response.body)
  rescue RestClient::Unauthorized
    puts 'WARNING: Skipping tenant_domains 401 error...'
    JSON.parse('{}')
  end

  # use tenant_list and tenant_domains to make a cached variable.
  # return cache in case it was already fetched.
  def tenant_mapping
    return @tenants if @tenants.length.positive?

    tenant_list.each do |tenant|
      domain_list = tenant_domains(tenant['name'])
      domains = []

      # add all domains belonging to a tenant
      domain_list.each do |dom|
        domains << dom['name']
      end

      # we don't need a name anymore just a flat list of all available
      # domains
      @tenants.concat domains
    end

    @tenants
  end

  # use cached tenant mapping to lookup bucket
  # that matches the forwarded_host passed in from HTTP_HOST header
  def default_bucket(forwarded_host)
    gateway_domains = tenant_mapping
    forwarded_domain = forwarded_host.split(':')[0] # strip port off
    bucket = ''

    # if host domain inside one of the gateway domains, strip gateway and whats left is the bucket
    gateway_domains.each do |dom|
      domain_name = dom.split(':')[0]
      if forwarded_domain.include?(domain_name)
        bucket = forwarded_domain.sub(domain_name, '')
        bucket.gsub!(/\.+$/, '') # remove trailing '.'
      end
    end

    bucket
  end
end
