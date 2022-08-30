# frozen_string_literal: true

require './app'
require 'test/unit'
require 'rack/test'
require 'webmock/test_unit'

require 'sidekiq/testing'
# require ... tenant mapping here
Sidekiq::Testing.inline!

ENV['S3_SERVER'] = 'http://s3-testing.be:888'
ENV['TENANT_API'] = 'http://s3-testing.be:888'

#
# S3 proxied calls initial tests
#
class ProxyTests < Test::Unit::TestCase
  include Rack::Test::Methods
  include WebMock::API

  NGINX_SERVER = (ENV['NGINX_SERVER'] || 'http://localhost:9090')
  S3_SERVER = 'http://s3-testing.be:888'

  def app
    S3ProxyApp
  end

  def setup
    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: '{}', headers: {})
  end

  def test_it_shows_api_information_page
    get '/'
    assert last_response.ok?
    assert last_response.body.include?('S3 proxy')
    assert last_response.body.include?('PUT')
    assert last_response.body.include?('GET')
  end

  def set_aws_signature_headers
    header 'Authorization', 'AWS4-HMAC-SHA256 Credential=shahashhere, SignedHeaders=cache-control;content-type;host;x-amz-date, Signature=signedhash'
    header 'X-Forwarded-Host', ENV['S3_SERVER']
  end

  def stub_s3_request(method, path, status_code)
    stub_request(method, "#{S3_SERVER}#{path}").with(
      headers: {
        'Accept' => '*/*',
        'Authorization' => 'AWS4-HMAC-SHA256 Credential=shahashhere, SignedHeaders=cache-control;content-type;host;x-amz-date, Signature=signedhash',
        'Range' => 'bytes=0-1'
        # 'X-Amz-Content-Sha256' => '',
        # 'X-Amz-Date' => ''
      }
    ).to_return(status: status_code, body: '', headers: {})
  end

  def stub_mediahaven_request(method: :get, api_route: '/', data: '{}', data_file: nil, status_code: 200)
    response = data
    response = File.read("test/data/#{data_file}") if data_file

    stub_request(method, "https://media-api-tests.be/resources#{api_route}")
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Content-Type' => 'application/json',
          'Host' => 'media-api-tests.be'
        }
      )
      .to_return(status: status_code, body: response, headers: {})
  end

  # TODO: remove code duplication (this is also in tenant_api test)
  # we need to move this into seperate file thats imported here...
  def tenant_mapping_stubs
    tenant_response = '[{"name":"or-w66976m","lastModified":"2019-03-25T15:20:33.996000Z",'\
                      '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",'\
                      '"etag":"39088c641f6bdad7ac97d0bae2b9edee"},'\
                      '{"name":"OR-tenantBucket","lastModified":"2019-03-25T14:17:46.944000Z",'\
                      '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",'\
                      '"etag":"0f84c523b55f92716a4ea65c8a097b23"},'\
                      '{"name":"gateway","lastModified":"2019-04-04T13:11:47.176000Z",'\
                      '"owner":"testuser.test@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",'\
                      '"etag":"4d1a498a03d36d12ab2460c3b588ec3d"}]'

    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip, deflate',
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
          'Accept-Encoding' => 'gzip, deflate',
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: '[]', headers: {})

    # filled in response
    vrt_tenant = '[{"name":"OR-tenantBucket.s3-testing.be",'\
              '"lastModified":"2019-03-25T14:32:38.816000Z",'\
              '"owner":"admin@","contentMd5":"1B2M2Y8AsgTpgAmY7PhCfg==",'\
              '"etag":"700a03b2c34998f3880982a20a031969"}]'

    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants/OR-tenantBucket/domains')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip, deflate',
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: vrt_tenant, headers: {})

    # gateway response test
    gateway_tenant =  '[{"name":"s3-testing.be","lastModified":"2019-04-04T13:12:34.148000Z",'\
                      '"owner":"test.testuser@","contentMd5":"test==",'\
                      '"etag":"teste5fc1fcfeea9cF136dce94f4e7aa"}]'
    stub_request(:get, 'http://s3-testing.be:888/_admin/manage/tenants/gateway/domains')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip, deflate',
          'Content-Type' => 'application/json',
          'Host' => 's3-testing.be:888'
        }
      )
      .to_return(status: 200, body: gateway_tenant, headers: {})
  end

  # ^^^^ above code needs to go into helper or fixture

  def test_download_existing_file
    # by giving a 200 back we simulate existing file and correct credentials
    # stub_s3_request(:get, '/lowres/README.md', 200)
    stub_mediahaven_request(
      api_route: '/media?nrOfResults=25&q=%2B(s3_object_key:%22README.md%22)%20%2B(s3_bucket:%22lowres%22)%20-(Type:videofragment)&startIndex=0',
      data_file: 'mediahaven_list_objects.json'
    )

    set_aws_signature_headers
    get '/lowres/README.md'

    puts "STATUS=#{last_response.status}"
    assert last_response.status == 403
    assert last_response.body.include? 'archived'
  end

  def test_failed_download
    # s3 server file not found 404
    stub_mediahaven_request(
      api_route: '/media?nrOfResults=25&q=%2B(s3_object_key:%22removed_file%22)%20%2B(s3_bucket:%22lowres%22)%20-(Type:videofragment)&startIndex=0',
      data: '{"totalNrOfResults":0, "startIndex":0, "mediaDataList":[]}'
    )

    set_aws_signature_headers
    get '/lowres/removed_file'

    assert last_response.status == 404
    assert last_response.body == 'File not found'
  end

  def test_get_on_key_with_slashes
    # extra slashes in s3 key (bucket is lowres here)
    # stub_s3_request(:get, '/lowres/some/random/slashed/key', 200)
    stub_mediahaven_request(
      api_route: '/media?nrOfResults=25&q=%2B(s3_object_key:%22some%2Frandom%2Fslashed%2Fkey%22)%20%2B(s3_bucket:%22lowres%22)%20-(Type:videofragment)&startIndex=0',
      data_file: 'mediahaven_list_objects.json'
    )

    set_aws_signature_headers
    get '/lowres/some/random/slashed/key'

    # assert last_response.ok?
    assert last_response.status == 403
  end

  ## put is completely handled by Caringo now
  # def test_put_on_key_with_slashes
  #  # put request for uploads
  #  stub_s3_request(:put, '/lowres/some/random/slashed/key', 200)
  #  set_aws_signature_headers
  #  put '/lowres/some/random/slashed/key'
  #  assert last_response.ok?
  # end

  # def test_post_on_key_with_slashes
  #   # post used for multipart uploads
  #   stub_s3_request(:post, '/lowres/some/random/slashed/key', 200)

  #   set_aws_signature_headers
  #   post '/lowres/some/random/slashed/key'

  #   assert last_response.ok?
  # end

  def test_unauthorized_download
    # when s3 caringo gives back 403 error
    # stub_s3_request(:get, '/lowres/unknown_file', 403)
    stub_mediahaven_request(
      api_route: '/media?nrOfResults=25&q=%2B(s3_object_key:%22unknown_file%22)%20%2B(s3_bucket:%22lowres%22)%20-(Type:videofragment)&startIndex=0',
      data_file: 'mediahaven_list_objects.json'
    )

    set_aws_signature_headers
    get '/lowres/unknown_file'

    assert last_response.status == 403
    assert last_response.body.include?('archived')
  end

  # TODO: change this test ...
  # def test_s3_server_error
  #  # when s3 caringo gives back a 400 error
  #  #stub_s3_request(:get, '/badbucket/unknown_file', 400)
  #  stub_mediahaven_get(
  #    '/media?nrOfResults=25&q=%2B(originalFileName:unknown_file)%20-(Type:videofragment)&startIndex=0',
  #    'mediahaven_list_objects.json',
  #    200
  #  )

  #  set_aws_signature_headers
  #  get '/badbucket/unknown_file'

  #  puts "status=#{last_response.status} body=#{last_response.body}"
  #  assert last_response.status == 400
  #  assert last_response.body.include?('Bad')
  # end

  # TODO : test 403 for archived files here !

  def test_status_file
    # this stub also returns content length like minio does
    stub_request(:head, "#{S3_SERVER}/lowres/README.md").with(
      headers: {
        'Accept' => '*/*',
        'Authorization' => 'AWS4-HMAC-SHA256 Credential=shahashhere, SignedHeaders=cache-control;content-type;host;x-amz-date, Signature=signedhash'
      }
    ).to_return(status: 200, body: '', headers: { 'Content-Length': 789 })

    set_aws_signature_headers

    stub_mediahaven_request(
      api_route: '/media?nrOfResults=25&q=%2B(s3_object_key:%22README.md%22)%20%2B(s3_bucket:%22lowres%22)%20-(Type:videofragment)&startIndex=0',
      data_file: 'mediahaven_list_objects.json'
    )

    # make status req
    head '/lowres/README.md'

    assert last_response.ok?
    assert last_response.status == 200

    # nginx renames this into x-amz-restore
    assert last_response.headers['x-amz-meta-amz-restore'].include?('ongoing-request="false", expiry-date="')
  end

  def test_status_file_not_found
    # restore request with 404 error (this should trigger other code in our app to call mediahaven)
    stub_request(:head, "#{S3_SERVER}/lowres/during_restore").with(
      headers: {
        'Accept' => '*/*'
      }
    ).to_return(status: 404, body: '', headers: { 'Content-Length': 0 })

    stub_mediahaven_request(
      api_route: '/media?nrOfResults=25&q=%2B(s3_object_key:%22during_restore%22)%20%2B(s3_bucket:%22lowres%22)%20-(Type:videofragment)&startIndex=0',
      data: '{"totalNrOfResults":0}'
    )

    tenant_mapping_stubs

    set_aws_signature_headers
    head '/lowres/during_restore'
    assert last_response.status == 404
    # assert last_response.headers['x-amz-restore'].include?('ongoing-request="false"')
  end

  # def test_status_file_restoring
  #   # make sure redis cache does not break test
  #   post '/clear_redis'

  #   tenant_mapping_stubs

  #   # file lookup request to mediahaven (return 1 result)
  #   stub_mediahaven_request(
  #     api_route: "/media?nrOfResults=25&q=%2B(s3_object_key:%22somefile%22)%20%2B(s3_bucket:%22somebucket%22)%20-(Type:videofragment)&startIndex=0",
  #     data_file: "mediahaven_list_objects.json",
  #   )

  #   stub_mediahaven_request(
  #     method: :post,
  #     api_route: '/media/123/export/1188',
  #     data: '{"exportId": "1234", "exportStatus": "created"}'
  #   )

  #   stub_request(:head, "#{S3_SERVER}/somebucket/somefile").with(
  #     headers: {
  #       'Accept' => '*/*'
  #     }
  #   ).to_return(status: 200, body: '', headers: { 'Content-Length': 789 })

  #   # export request to mediahaven
  #   stub_mediahaven_request(api_route: '/exports/', data: '')

  #   # mediahaven export from tape to s3 request
  #   stub_mediahaven_request(
  #     method: :post,
  #     api_route: '/media/abc1234/export/1188',
  #     data: '[{"status" :"created", "exportId": "some_export_id11334", "progress": 0}]'
  #   )

  #   # mediahaven export status call
  #   stub_mediahaven_request(
  #     api_route: '/exports/some_export_id11334',
  #     data: '[{"status":"completed", "progres":100, "exportId": "some_export_id11334"}]'
  #   )

  #   # moving file to original location (first a search call is done on umid then copy is called)
  #   restore_search_xml = File.read('test/data/restore_search.xml')

  #   stub_request(:get, 'http://s3-testing.be:888/somebucket/?domain=example.org&format=xml&prefix=abc1234')
  #     .with(
  #       headers: {
  #         'Accept' => '*/*',
  #         'Accept-Encoding' => 'gzip, deflate',
  #         'Host' => 's3-testing.be:888'
  #       }
  #     )
  #     .to_return(status: 200, body: restore_search_xml, headers: {})

  #   stub_request(:copy, 'http://s3-testing.be:888/somebucket/somefile_target.mp4?domain=example.org&newname=somefile')
  #     .with(
  #       headers: {
  #         'Accept' => '*/*',
  #         'Accept-Encoding' => 'gzip, deflate',
  #         # 'Content-Type' => 'video/mp4',
  #         'Host' => 's3-testing.be:888',
  #         'X-Viaa-Meta-Cpid' => 'iOR-cpidstring'
  #       }
  #     )
  #     .to_return(status: 200, body: '', headers: {})

  #   post '/somebucket/somefile?restore'

  #   # puts "last status=#{last_response.status}  \nlast response=#{last_response.body}"
  #   assert last_response.status == 201
  #   assert JSON.parse(last_response.body)['status'] == 'created'

  #   head '/somebucket/somefile'
  #   assert last_response.ok?
  # end
end
