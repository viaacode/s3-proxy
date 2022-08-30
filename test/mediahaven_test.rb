# frozen_string_literal: true

require './app'
require 'test/unit'
require 'rack/test'
require 'webmock/test_unit'

ENV['MEDIAHAVEN_API'] = 'https://media-api-tests.be'
ENV['TENANT_API'] = 'http://s3-testing.be:888'

#
# Test MediahavenApi calls
#
class MediaHavenTests < Test::Unit::TestCase
  include Rack::Test::Methods
  include WebMock::API

  def app
    S3ProxyApp
  end

  def setup
    @mediahaven_api = MediahavenApi.new
  end

  def stub_mediahaven_get(api_url, response_file, status_code = 200)
    data = File.read("test/data/#{response_file}")
    stub_request(:get, "https://media-api-tests.be/resources#{api_url}")
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Content-Type' => 'application/json',
          'Host' => 'media-api-tests.be'
        }
      )
      .to_return(status: status_code, body: data, headers: {})
  end

  def stub_mediahaven_post(api_url, response_file, status_code = 200)
    data = File.read("test/data/#{response_file}")
    stub_request(:post, "https://media-api-tests.be/resources#{api_url}")
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Content-Type' => 'application/json',
          'Host' => 'media-api-tests.be'
        }
      )
      .to_return(status: status_code, body: data, headers: {})
  end

  def test_listing_objects
    stub_mediahaven_get(
      '/media?nrOfResults=25&q=&startIndex=0',
      'mediahaven_list_objects.json'
    )

    response = @mediahaven_api.list_objects
    assert response['totalNrOfResults'] == 3
    assert response['mediaDataList'].length == 3
    assert response['mediaDataList'][2]['originalFileName'] == 'qs09h41k92c.mp4'
  end

  def test_object_searching
    stub_mediahaven_get(
      '/media?nrOfResults=25&q=%2B(originalFileName:qs09h41k92c.mp4)&startIndex=0',
      'mediahaven_search_objects.json'
    )

    response = @mediahaven_api.list_objects(search: '+(originalFileName:qs09h41k92c.mp4)')
    assert response['totalNrOfResults'] == 1
    assert response['mediaDataList'].length == 1
    assert response['mediaDataList'][0]['originalFileName'] == 'qs09h41k92c.mp4'
  end

  def test_get_object
    stub_mediahaven_get(
      '/media?nrOfResults=25&q=%2B(originalFileName:qs09h41k92c.mp4)&startIndex=0',
      'mediahaven_search_objects.json'
    )

    stub_mediahaven_get(
      '/media/42ac852bfbdb495e83c74409981c135665c28dd9cdf545c082260a00de4b9bf5',
      'mh_get_object.json'
    )

    response = @mediahaven_api.list_objects(search: '+(originalFileName:qs09h41k92c.mp4)')
    obj_id = response['mediaDataList'][0]['mediaObjectId']

    response = @mediahaven_api.get_object(obj_id)
    assert response['originalFileName'] == 'qs09h41k92c.mp4'
    assert response['externalId'] == 'qs09h41k92c'
    assert response['mediaObjectId'] == '42ac852bfbdb495e83c74409981c135665c28dd9cdf545c082260a00de4b9bf5'
  end

  def test_lookup_s3_path
    # stub_mediahaven_get(
    #  '/media?nrOfResults=25&q=%2B(s3_object_key:qs09h41k92c.mp4)%20%2B(s3_bucket:OR-tenantBucket)%20-(Type:videofragment)&startIndex=0',
    #  's3_lookup_response.json'
    # )

    stub_mediahaven_get(
      '/media?nrOfResults=25&q=%2B(s3_object_key:%22qs09h41k92c.mp4%22)%20%2B(s3_bucket:%22OR-tenantBucket%22)%20-(Type:videofragment)&startIndex=0',
      's3_lookup_response.json'
    )

    stub_mediahaven_get(
      '/media?nrOfResults=25&q=%2B(s3_object_key:qs09h41k92c.mp4)%20%2B(s3_bucket:OR-tenantBucket)%20-(Type:videofragment)&startIndex=0',
      's3_lookup_response.json'
    )

    response = @mediahaven_api.lookup_s3_path('OR-tenantBucket', 'qs09h41k92c.mp4')

    assert response[:media_id] == '42ac852bfbdb495e83c74409981c135665c28dd9cdf545c082260a00de4b9bf568a8e327aafa4b6996afc769a51e03d9'
  end

  def test_export
    # test audio file
    object_id = '92b8c18e863a4b19ae8aff1b73d4384355dfe2bd87af4be5b273987f417e1289'
    stub_mediahaven_post(
      "/media/#{object_id}/export/#{ENV['EXPORT_LOCATION_ID']}",
      'mh_export_response.json'
    )

    response = @mediahaven_api.export(object_id, 'reason is testing')
    assert response['status'] == 'created'
    assert !response['exportId'].empty?
  end

  def test_export_locations
    stub_mediahaven_get(
      '/exportlocations',
      'mh_export_locations.json'
    )

    response = @mediahaven_api.export_locations
    assert response.length == 8
    assert response[0]['name'] == 'Archief voor Onderwijs'
  end

  def test_export_status_starting
    export_id = '20190419_170656_c10be36e5cb14ce1ac7c3da1eb697efdcd56dc9558054241acd89558e654acd8_viaa@viaa_7b02b2dc-d52d-4b51-af63-2b88685a8dba'
    stub_mediahaven_get(
      "/exports/#{export_id}",
      'mh_export_status_starting.json'
    )

    response = @mediahaven_api.export_status(export_id)

    assert response['status'] == 'in_progress'
    assert response['progress'].zero?
    assert response['exportId'] == export_id
  end

  def test_export_status_halfway
    export_id = '20190419_170656_c10be36e5cb14ce1ac7c3da1eb697efdcd56dc9558054241acd89558e654acd8_viaa@viaa_7b02b2dc-d52d-4b51-af63-2b88685a8dba'
    stub_mediahaven_get(
      "/exports/#{export_id}",
      'mh_export_status_halfway.json'
    )

    response = @mediahaven_api.export_status(export_id)

    assert response['status'] == 'in_progress'
    assert response['progress'] == 37
    assert response['exportId'] == export_id
  end

  def test_export_status_completed
    export_id = '20190419_170656_c10be36e5cb14ce1ac7c3da1eb697efdcd56dc9558054241acd89558e654acd8_viaa@viaa_7b02b2dc-d52d-4b51-af63-2b88685a8dba'
    stub_mediahaven_get(
      "/exports/#{export_id}",
      'mh_export_status_completed.json'
    )

    response = @mediahaven_api.export_status(export_id)
    assert response['status'] == 'completed'
    assert response['progress'] == 100
    assert response['exportId'] == export_id
  end

  #
  # these are currently not used in s3proxy
  #
  # def test_upload_file
  #  omit 'Upload file call for mediahaven test necessary?'
  # end

  # def test_publish_object
  #  omit 'Publish object mediahaven call test'
  # end

  # def test_delete_object
  #   omit 'Delete object call test'
  # end
end
