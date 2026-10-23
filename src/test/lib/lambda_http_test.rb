require 'test_helper'
require Rails.root.join('lambda_http')
require 'tempfile'

class LambdaHttpTest < ActiveSupport::TestCase
  test 'UTF-8 static stylesheets and scripts survive Lambda JSON serialization' do
    %w[css js].each do |extension|
      content = "/* café — 日本語 */\n"
      with_static_asset(extension, content) do |path|
        response = JSON.parse(JSON.generate(serve_static_file(path)))

        assert_equal 200, response.fetch('statusCode')
        assert_equal false, response.fetch('isBase64Encoded')
        assert_equal content, response.fetch('body')
        assert_equal content.bytesize.to_s, response.fetch('headers').fetch('Content-Length')
      end
    end
  end

  test 'non UTF-8 static text is safely base64 encoded without losing bytes' do
    content = "/* \xFF */".b
    with_static_asset('css', content) do |path|
      response = JSON.parse(JSON.generate(serve_static_file(path)))

      assert_equal 200, response.fetch('statusCode')
      assert_equal true, response.fetch('isBase64Encoded')
      assert_equal content, Base64.strict_decode64(response.fetch('body'))
    end
  end

  test 'returns a CSRF token and session cookie through API Gateway' do
    response = lambda_get('/en/csrf_token')

    assert_equal 200, response['statusCode']
    assert_equal 'authenticity_token', JSON.parse(response['body']).fetch('param')
    assert_predicate JSON.parse(response['body']).fetch('token'), :present?
    assert response.fetch('cookies').any? { |cookie| cookie.start_with?('_schengen_track_session=') }
    assert_match 'private', response.fetch('headers').fetch('Cache-Control')
    assert_match 'no-store', response.fetch('headers').fetch('Cache-Control')
    refute response.fetch('headers').key?('Set-Cookie')
  end

  test 'anonymous calculator HTML stays public and cookie free through API Gateway' do
    response = lambda_get('/en/visits')

    assert_equal 200, response['statusCode']
    assert_match 'text/html', response.fetch('headers').fetch('Content-Type')
    assert_match 'public', response.fetch('headers').fetch('Cache-Control')
    assert_empty response.fetch('cookies', [])
    refute_includes response.fetch('body'), 'name="csrf-token"'
  end

  test 'serves the OpenAPI document directly from the Lambda adapter' do
    event = {
      'requestContext' => {
        'stage' => '$default',
        'http' => { 'method' => 'GET', 'path' => '/openapi.json' }
      }
    }

    response = handler(event: event, context: nil)

    assert_equal 200, response['statusCode']
    assert_equal '3.1.0', JSON.parse(response['body']).fetch('openapi')
  end

  test 'client ip prefers CloudFront viewer header over forwarded chain' do
    http = { 'sourceIp' => '198.51.100.10' }
    headers = {
      'x-schengen-origin-auth' => 'cloudfront-secret',
      'x-schengen-client-ip' => '203.0.113.42',
      'x-forwarded-for' => '192.0.2.99, 203.0.113.42, 198.51.100.10'
    }

    with_cloudfront_origin_auth('cloudfront-secret') do
      assert_equal '203.0.113.42', client_ip_from(http, headers)
    end
  end

  test 'client ip uses first forwarded address from authenticated CloudFront chain' do
    http = { 'sourceIp' => '198.51.100.10' }
    headers = {
      'x-schengen-origin-auth' => 'cloudfront-secret',
      'x-forwarded-for' => '203.0.113.42, 198.51.100.10'
    }

    with_cloudfront_origin_auth('cloudfront-secret') do
      assert_equal '203.0.113.42', client_ip_from(http, headers)
    end
  end

  test 'client ip ignores spoofed CloudFront headers without origin auth' do
    http = { 'sourceIp' => '198.51.100.10' }
    headers = {
      'x-schengen-client-ip' => '203.0.113.42',
      'x-forwarded-for' => '203.0.113.42, 198.51.100.10'
    }

    with_cloudfront_origin_auth('cloudfront-secret') do
      assert_equal '198.51.100.10', client_ip_from(http, headers)
    end
  end

  test 'client ip ignores CloudFront headers with mismatched origin auth' do
    http = { 'sourceIp' => '198.51.100.10' }
    headers = {
      'x-schengen-origin-auth' => 'wrong-secret',
      'x-schengen-client-ip' => '203.0.113.42',
      'x-forwarded-for' => '203.0.113.42, 198.51.100.10'
    }

    with_cloudfront_origin_auth('cloudfront-secret') do
      assert_equal '198.51.100.10', client_ip_from(http, headers)
    end
  end

  test 'client ip falls back to API Gateway source ip' do
    http = { 'sourceIp' => '198.51.100.10' }

    assert_equal '198.51.100.10', client_ip_from(http, {})
  end

  private

  def with_static_asset(extension, content)
    file = Tempfile.new(['lambda-asset-', ".#{extension}"], Rails.root.join('public'))
    file.binmode
    file.write(content)
    file.close
    yield "/#{File.basename(file.path)}"
  ensure
    file&.unlink
  end

  def lambda_get(path)
    event = {
      'requestContext' => {
        'stage' => '$default',
        'http' => { 'method' => 'GET', 'path' => path, 'sourceIp' => '127.0.0.1' }
      },
      'rawQueryString' => '',
      'headers' => {
        'host' => 'www.example.com',
        'x-forwarded-port' => '443',
        'x-forwarded-proto' => 'https'
      }
    }
    context = Struct.new(:aws_request_id).new('lambda-http-test')

    handler(event: event, context: context)
  end

  def with_cloudfront_origin_auth(secret)
    original = ENV['CLOUDFRONT_ORIGIN_AUTH_HEADER']
    ENV['CLOUDFRONT_ORIGIN_AUTH_HEADER'] = secret
    yield
  ensure
    if original.nil?
      ENV.delete('CLOUDFRONT_ORIGIN_AUTH_HEADER')
    else
      ENV['CLOUDFRONT_ORIGIN_AUTH_HEADER'] = original
    end
  end
end
