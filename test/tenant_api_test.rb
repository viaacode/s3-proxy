# frozen_string_literal: true

require './app'
require 'test/unit'
require 'rack/test'
require 'webmock/test_unit'

ENV['TENANT_API'] = 'http://s3-testing.be:888'

#
# Tenant api tests
#
class TenantApiTests < Test::Unit::TestCase
  include Rack::Test::Methods
  include WebMock::API
  ENCODING_HEADER = 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3'

  def app
    S3ProxyApp
  end

  def setup
    @tenant_api = TenantApi.new
  end

  def test_tenant_list
    tenant_response = '[{"name":"or-w66976m","lastModified":"2019-03-25T15:20:33.996000Z",' \
                      '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"39088c641f6bdad7ac97d0bae2b9edee"},' \
                      '{"name":"OR-tenantBucket","lastModified":"2019-03-25T14:17:46.944000Z",' \
                      '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"0f84c523b55f92716a4ea65c8a097b23"},' \
                      '{"name":"gateway","lastModified":"2019-04-04T13:11:47.176000Z",' \
                      '"owner":"testuser.testing@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"4d1a498a03d36d12ab2460c3b588ec3d"}]'

    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200,
                 body: tenant_response,
                 headers: {})

    s3_tenants = @tenant_api.tenant_list

    assert s3_tenants.length == 3
    assert s3_tenants[1]['name'] == 'OR-tenantBucket'
  end

  def test_tenant_domains_call
    domain_response = '[{"name":"OR-tenantBucket.s3-testing.be:888",' \
                      '"lastModified":"2019-03-25T14:32:38.816000Z",' \
                      '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"700a03b2c34998f3880982a20a031969"}]'

    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants/OR-tenantBucket/domains')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: domain_response, headers: {})

    s3_domains = @tenant_api.tenant_domains('OR-tenantBucket')

    # array with one entry here
    assert s3_domains.length == 1

    # notice port number is not here
    assert s3_domains[0]['name'] == 'OR-tenantBucket.s3-testing.be:888'
  end

  def tenant_mapping_stubs
    tenant_response = '[{"name":"or-w66976m","lastModified":"2019-03-25T15:20:33.996000Z",' \
                      '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"39088c641f6bdad7ac97d0bae2b9edee"},' \
                      '{"name":"OR-tenantBucket","lastModified":"2019-03-25T14:17:46.944000Z",' \
                      '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"0f84c523b55f92716a4ea65c8a097b23"},' \
                      '{"name":"gateway","lastModified":"2019-04-04T13:11:47.176000Z",' \
                      '"owner":"testuser.testing@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"4d1a498a03d36d12ab2460c3b588ec3d"}]'

    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: tenant_response, headers: {})

    # example of empty domain response
    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants/or-w66976m/domains')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: '[]', headers: {})

    # filled in response
    vrt_tenant =  '[{"name":"OR-tenantBucket.s3-testing.be:888",' \
                  '"lastModified":"2019-03-25T14:32:38.816000Z",' \
                  '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                  '"etag":"700a03b2c34998f3880982a20a031969"}]'

    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants/OR-tenantBucket/domains')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: vrt_tenant, headers: {})

    # gateway response test
    gateway_tenant =  '[{"name":"s3-testing.be:888","lastModified":"2019-04-04T13:12:34.148000Z",' \
                      '"owner":"testuser.testing@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"5a9be5fc1fcfeea9ce136dce94f4e7aa"}]'
    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants/gateway/domains')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: gateway_tenant, headers: {})
  end

  def tenant_mapping_stubs_gateway
    tenant_response = '[' \
                      '{"name":"gateway","lastModified":"2019-04-04T13:11:47.176000Z",' \
                      '"owner":"testuser.testing@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"4d1a498a03d36d12ab2460c3b588ec3d"}]'

    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: tenant_response, headers: {})

    # gateway response test
    gateway_tenant =  '[{"name":"s3-testing.be:888","lastModified":"2019-04-04T13:12:34.148000Z",' \
                      '"owner":"testuser.testing@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",' \
                      '"etag":"5a9be5fc1fcfeea9ce136dce94f4e7aa"}]'
    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants/gateway/domains')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => ENCODING_HEADER,
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: gateway_tenant, headers: {})
  end

  def test_tenant_mapping_call
    tenant_mapping_stubs
    s3_mapping_response = @tenant_api.tenant_mapping
    correct_s3_mapping = [
      'OR-tenantBucket.s3-testing.be:888',
      's3-testing.be:888'
    ]

    assert s3_mapping_response.length == 2
    assert s3_mapping_response == correct_s3_mapping
  end

  def test_default_bucket_calls
    tenant_mapping_stubs_gateway
    vrt_bucket = @tenant_api.default_bucket('OR-tenantBucket.s3-testing.be:888')

    assert vrt_bucket == 'OR-tenantBucket'

    gateway_bucket = @tenant_api.default_bucket('s3-testing.be:888')
    assert gateway_bucket == ''
  end
end
