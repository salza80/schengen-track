require 'test_helper'
require Rails.root.join('lambda_http')
require 'tempfile'
require 'rack/lint'

class LambdaHttpTest < ActiveSupport::TestCase
  test 'redirects preserve separate cookies and other multi-value headers' do
    cookies = ['first=1; Path=/', 'second=2; Expires=Wed, 21 Oct 2030 07:28:00 GMT']
    headers = { 'location' => '/en/visits', 'set-cookie' => cookies, 'vary' => ['Accept', 'Cookie'] }
    with_rack_app(->(_env) { [302, headers, ['redirect']] }) do
      response = lambda_get('/redirect')
      assert_equal 302, response.fetch('statusCode')
      assert_equal cookies, response.fetch('cookies')
      assert_equal '/en/visits', response.fetch('headers').fetch('location')
      assert_equal 'Accept,Cookie', response.fetch('headers').fetch('vary')
      refute response.fetch('headers').key?('set-cookie')
      assert_equal cookies, headers.fetch('set-cookie')
    end
  end

  test 'decoded request bodies cookies and content length satisfy Rack 3' do
    app = ->(env) do
      payload = { body: env.fetch('rack.input').read, length: env.fetch('CONTENT_LENGTH'),
                  cookie: env['HTTP_COOKIE'], query: env['QUERY_STRING'], protocol: env['SERVER_PROTOCOL'] }
      [200, { 'content-type' => 'application/json' }, [JSON.generate(payload)]]
    end
    with_rack_app(Rack::Lint.new(app)) do
      event = lambda_event('/request')
      event['requestContext']['http']['method'] = 'POST'
      event['body'] = Base64.strict_encode64('name=caf%C3%A9')
      event['isBase64Encoded'] = true
      event['cookies'] = ['first=1', 'second=2']
      event['headers']['content-length'] = '999'
      response = handler(event: event, context: lambda_context)
      assert_equal 200, response.fetch('statusCode'), response['body']
      payload = JSON.parse(response.fetch('body'))
      assert_equal 'name=caf%C3%A9', payload.fetch('body')
      assert_equal '14', payload.fetch('length')
      assert_equal 'first=1; second=2', payload.fetch('cookie')
      assert_equal '', payload.fetch('query')
      assert_equal 'HTTP/1.1', payload.fetch('protocol')
    end
  end

  test 'static binary files and HEAD responses preserve bytes and length' do
    content = "\x89PNG\r\n\xFF".b
    with_static_asset('png', content) do |path|
      response = JSON.parse(JSON.generate(serve_static_file(path)))
      assert_equal 200, response.fetch('statusCode')
      assert_equal true, response.fetch('isBase64Encoded')
      assert_equal content, Base64.strict_decode64(response.fetch('body'))
      head = serve_static_file(path, method: 'HEAD')
      assert_equal 200, head.fetch('statusCode')
      assert_equal '', head.fetch('body')
      assert_equal content.bytesize.to_s, head.fetch('headers').fetch('content-length')
    end
    assert_equal 404, serve_static_file('/missing-rack3-asset.css').fetch('statusCode')
  end

  test 'dynamic HEAD responses close bodies without enumerating them' do
    body = Object.new
    closed = false
    body.define_singleton_method(:each) { raise 'HEAD must not enumerate the body' }
    body.define_singleton_method(:close) { closed = true }
    with_rack_app(->(_env) { [200, { 'content-type' => 'text/html' }, body] }) do
      event = lambda_event('/head')
      event['requestContext']['http']['method'] = 'HEAD'
      response = handler(event: event, context: lambda_context)
      assert_equal 200, response.fetch('statusCode')
      assert_equal '', response.fetch('body')
      assert closed
    end
  end

  test 'dynamic binary responses are encoded and closed' do
    bytes = "\x00\xFF".b
    body = Object.new
    closed = false
    body.define_singleton_method(:each) { |&block| block.call(bytes) }
    body.define_singleton_method(:close) { closed = true }
    with_rack_app(->(_env) { [200, { 'content-type' => 'application/octet-stream' }, body] }) do
      response = JSON.parse(JSON.generate(lambda_get('/binary')))
      assert_equal 200, response.fetch('statusCode')
      assert_equal true, response.fetch('isBase64Encoded')
      assert_equal bytes, Base64.strict_decode64(response.fetch('body'))
      assert closed
    end
  end

  test 'body failures close resources and return a safe error' do
    body = Object.new
    closed = false
    body.define_singleton_method(:each) { raise 'private error detail' }
    body.define_singleton_method(:close) { closed = true }
    with_rack_app(->(_env) { [200, {}, body] }) do
      capture_io do
        response = lambda_get('/failure')
        assert_equal 500, response.fetch('statusCode')
        assert_equal 'Internal Server Error', response.fetch('body')
      end
      assert closed
    end
  end

  test 'call-only streaming bodies are rejected and closed' do
    body = Object.new
    closed = false
    body.define_singleton_method(:call) { |_stream| flunk 'must not start streaming' }
    body.define_singleton_method(:close) { closed = true }
    with_rack_app(->(_env) { [200, {}, body] }) do
      capture_io { assert_equal 500, lambda_get('/stream').fetch('statusCode') }
      assert closed
    end
  end

  test 'UTF-8 static stylesheets and scripts survive Lambda JSON serialization' do
    %w[css js].each do |extension|
      content = "/* café — 日本語 */\n"
      with_static_asset(extension, content) do |path|
        response = JSON.parse(JSON.generate(serve_static_file(path)))

        assert_equal 200, response.fetch('statusCode')
        assert_equal false, response.fetch('isBase64Encoded')
        assert_equal content, response.fetch('body')
        assert_equal content.bytesize.to_s, response.fetch('headers').fetch('content-length')
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
    assert_match 'private', response.fetch('headers').fetch('cache-control')
    assert_match 'no-store', response.fetch('headers').fetch('cache-control')
    refute response.fetch('headers').key?('set-cookie')
  end

  test 'anonymous calculator HTML stays public and cookie free through API Gateway' do
    response = lambda_get('/en/visits')

    assert_equal 200, response['statusCode']
    assert_match 'text/html', response.fetch('headers').fetch('content-type')
    assert_match 'public', response.fetch('headers').fetch('cache-control')
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

  test 'viewer identity requires the exact IAM signer role, never the old bearer' do
    with_signer_role do
      headers = { 'x-schengen-client-ip' => '203.0.113.42',
                  'x-forwarded-for' => '192.0.2.99', 'x-schengen-origin-auth' => 'old-secret' }
      context = signer_context
      assert_equal '203.0.113.42', client_ip_from(context, headers)
      [nil, 'arn:aws:sts::123456789012:assumed-role/OtherRole/session',
       'arn:aws:sts::999999999999:assumed-role/OriginSigner/session',
       'arn:aws:sts::123456789012:assumed-role/OriginSignerExtra/session',
       'arn:aws:iam::123456789012:role/OriginSigner'].each do |caller|
        context['authorizer']['iam']['userArn'] = caller
        assert_equal '198.51.100.10', client_ip_from(context, headers)
      end
    end
  end

  test 'verified signer never falls back to a viewer supplied forwarded chain' do
    with_signer_role do
      assert_equal '198.51.100.10', client_ip_from(signer_context, 'x-forwarded-for' => '192.0.2.99')
      assert_equal '198.51.100.10', client_ip_from(signer_context, 'x-schengen-client-ip' => 'bad,203.0.113.1')
    end
  end

  test 'origin rejection precedes static files and application work' do
    with_signer_role do
      ['/openapi.json', '/en/visits'].each do |path|
        event = lambda_event(path)
        event['headers']['x-schengen-origin-auth'] = 'old-secret'
        event['headers']['x-schengen-client-ip'] = '203.0.113.42'
        result = handler(event: event, context: lambda_context)
        assert_equal 403, result['statusCode']
        assert_equal 'private, no-store', result['headers']['cache-control']
      end
      event = lambda_event('/openapi.json')
      event['requestContext']['authorizer'] = signer_context['authorizer']
      assert_equal 200, handler(event: event, context: lambda_context)['statusCode']
    end
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

  def with_rack_app(app)
    original = $app
    $app = app
    yield
  ensure
    $app = original
  end

  def lambda_event(path)
    {
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
  end

  def lambda_context
    Struct.new(:aws_request_id).new('lambda-http-test')
  end

  def lambda_get(path)
    handler(event: lambda_event(path), context: lambda_context)
  end

  def signer_context
    { 'http' => { 'sourceIp' => '198.51.100.10' },
      'authorizer' => { 'iam' => { 'userArn' => 'arn:aws:sts::123456789012:assumed-role/OriginSigner/session' } } }
  end

  def with_signer_role
    original = ENV['CLOUDFRONT_SIGNER_ROLE_ARN']
    ENV['CLOUDFRONT_SIGNER_ROLE_ARN'] = 'arn:aws:iam::123456789012:role/OriginSigner'
    yield
  ensure
    original.nil? ? ENV.delete('CLOUDFRONT_SIGNER_ROLE_ARN') : ENV['CLOUDFRONT_SIGNER_ROLE_ARN'] = original
  end
end
