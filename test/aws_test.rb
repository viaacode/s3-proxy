# frozen_string_literal: true

require './app'
require 'test/unit'
require 'rack/test'
require 'webmock/test_unit'
require 'aws-sdk-s3'
# require 'aws-sdk' # for specific caringo s3 version

ENV['S3_SERVER'] = 'http://localhost:9999'
ENV['TENANT_API'] = 'http://s3-testing.be:888'

#
# Test some specific minio calls here using the amazon client
#
class AwsMinioTests < Test::Unit::TestCase
  include Rack::Test::Methods
  include WebMock::API

  NGINX_SERVER = (ENV['NGINX_SERVER'] || 'http://localhost:9090')
  S3_SERVER = ENV.fetch('S3_SERVER', nil)

  def app
    S3ProxyApp
  end

  def setup
    Aws.config.update(
      endpoint: NGINX_SERVER, # nginx url that is proxied to sinatra app and then redirects to minio
      access_key_id: 'TOPSECRET',
      secret_access_key: 'ViaaSecret2019/K7MDENG/bPxRfiCYEXAMPLEKEY',
      force_path_style: true,
      region: 'us-east-1'
    )

    @s3client = Aws::S3::Client.new
  end

  # helper method to easily stub out nginx get+head requests
  def stub_nginx_request(method, path, status_code)
    stub_request(method, "#{NGINX_SERVER}#{path}")
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => '',
          'Host' => 'localhost:9090'
          # future todo we might include some headers in authorization
          # this is tricky on gitlab however so right now we omit them here.
          # 'Authorization'=>'AWS4-HMAC-SHA256 Credential=TOP...',
          # 'X-Amz-Content-Sha256'=>'a948....99a192a447',
          # 'X-Amz-Date'=>'20190226T172353Z'
        }
      )
      .to_return(status: status_code, body: '', headers: {})
  end

  def test_upload
    file_data = File.read('test/data/file_test.txt')

    stub_request(:put, "#{NGINX_SERVER}/lowres/README.md")
      .with(
        body: "hello world\n",
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => '',
          'Host' => 'localhost:9090'
        }
      )
      .to_return(status: 200, body: '', headers: {})

    r = @s3client.put_object(
      key: 'README.md',
      body: file_data,
      bucket: 'lowres'
    )

    assert !r.nil?
  end

  def test_download
    stub_nginx_request(:get, '/lowres/README.md', 200)
    r = @s3client.get_object(
      key: 'README.md',
      bucket: 'lowres',
      response_target: 'test/data/download_test.txt'
    )
    assert !r.nil?
    # because this is a stubbed request file contents is empty here (empty body)
  end

  def test_status_request_on_archived
    stub_nginx_request(:head, '/highres/uploaded_video_unexisting.mp4', 404)
    begin
      response = @s3client.head_object(
        bucket: 'highres',
        key: 'uploaded_video_unexisting.mp4'
      )
      print "\nunexisting file response=#{response.to_h}"
    rescue Aws::S3::Errors::NotFound
      response = 'file not found'
    end
    assert response == 'file not found'

    # TODO: have mediahaven call here and either return real 404 or archived 403 response
    # omit('todo...')
  end

  def test_status_on_available_file
    stub_nginx_request(:head, '/lowres/README.md', 200)
    response = @s3client.head_object(
      bucket: 'lowres',
      key: 'README.md'
    )
    assert !response.nil?
  end

  def test_restore_request
    stub_nginx_request(:post, '/lowres/archivedobjectkey?restore', 200)
    rest_resp = @s3client.restore_object(
      bucket: 'lowres',
      key: 'archivedobjectkey',
      restore_request: {
        days: 1,
        glacier_job_parameters: {
          tier: 'Expedited'
        }
      }
    )
    assert !rest_resp.nil?
  end
end
