require 'json'
require 'rack'
require 'base64'
require 'stringio'

$app ||= Rack::Builder.parse_file("#{__dir__}/config.ru")

RELATIVE_URL_ROOT = ENV['RAILS_RELATIVE_URL_ROOT']

def client_ip_from(http, request_headers)
  if trusted_cloudfront_request?(request_headers)
    cloudfront_client_ip = request_headers['x-schengen-client-ip'] || request_headers['X-Schengen-Client-Ip']
    return cloudfront_client_ip.strip unless cloudfront_client_ip.to_s.strip.empty?

    forwarded_for = request_headers['x-forwarded-for'] || request_headers['X-Forwarded-For']
    forwarded_ip = forwarded_for.to_s.split(',').map(&:strip).find { |value| !value.empty? }
    return forwarded_ip if forwarded_ip
  end

  http['sourceIp']
end

def trusted_cloudfront_request?(request_headers)
  expected = AppConfig.cloudfront_origin_auth_header
  return false if expected.to_s.empty?

  provided = (request_headers['x-schengen-origin-auth'] || request_headers['X-Schengen-Origin-Auth']).to_s
  return false if provided.empty? || provided.bytesize != expected.bytesize

  Rack::Utils.secure_compare(provided, expected)
end

# Buffer Rack's enumerable responses for API Gateway HTTP API payload v2.
# Streaming (call-only) bodies require a different Lambda integration.
def lambda_response(status, headers, body, head: false)
  content = String.new(encoding: Encoding::BINARY)
  begin
    raise 'Streaming Rack bodies are not supported by this Lambda integration' unless body.respond_to?(:each)

    body.each { |part| content << part } unless head
  ensure
    body.close if body.respond_to?(:close)
  end

  text = content.dup.force_encoding(Encoding::UTF_8)
  base64 = !content.empty? && (is_binary_content?(headers) || !text.valid_encoding?)
  response = {
    'statusCode' => status,
    'headers' => headers.reject { |key, _| key == 'set-cookie' }.transform_values { |value| Array(value).join(',') },
    'body' => base64 ? Base64.strict_encode64(content) : text,
    'isBase64Encoded' => base64
  }
  cookies = headers['set-cookie']
  response['cookies'] = Array(cookies) if cookies
  response
end

def serve_static_file(path, method: 'GET')
  status, headers, body = Rack::Files.new(File.join(__dir__, 'public')).call(
    'PATH_INFO' => path, 'SCRIPT_NAME' => '', 'REQUEST_METHOD' => method
  )
  lambda_response(status, headers, body, head: method == 'HEAD')
end

# Function to determine if content type is binary
def is_binary_content?(headers)
  content_type = headers['content-type']

  # Return true if Content-Type header is not present
  return true if content_type.nil?

  binary_mime_types = [
    'application/octet-stream',
    'application/pdf',
    'application/zip',
    'application/gzip',
    'application/font*',
    'image/*',
    'audio/*',
    'video/*',
    'text/plain',
    'application/x-binary',
    'application/x-tar',
    'application/x-rar-compressed'
  ]

  binary_mime_types.any? do |pattern|
    content_type.include?(pattern.sub('*', ''))
  end
end


def handler(event:, context:)
  # Retrieve HTTP request parameters conforming to Lambda proxy integration input format 2.0 of AWS API Gateway HTTP API
  # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#http-api-develop-integrations-lambda.proxy-format
  requestContext = event.fetch('requestContext')
  http = requestContext.fetch('http')
  httpMethod = http.fetch('method')
  protocol = http['protocol'] || 'HTTP/1.1'
  path = http.fetch('path')

  # In input format 2.0, the path always contains a stage
  stage = requestContext['stage'] || '$default'
  if stage != '$default'
    path = path.sub(/\A\/#{Regexp.escape(stage)}(?=\/|\z)/, '')
    path = '/' if path.empty?
  end

  # Explicitly serve static SEO files as static files
  # These must be handled before API format checking since .txt and .xml are considered API formats
  # Handle: robots.txt, llms.txt, ads.txt, openapi.json, sitemap.xml, sitemap-*.xml
  if path == '/robots.txt' || path == '/llms.txt' || path == '/llms-full.txt' || path == '/ads.txt' || path == '/openapi.json' || path == '/sitemap.xml' || path.start_with?('/sitemap')
    response = serve_static_file(path, method: httpMethod)
    return response if response['statusCode'] != 404
  end
  
  # Check if the request is for a static file
  # Only serve actual static files (assets, public directory, or file extensions that aren't API formats)
  extname = File.extname(path)
  is_api_format = ['.json', '.xml', '.csv', '.js', '.html', '.txt'].include?(extname)
  
  if (path.start_with?('/assets/') || path.start_with?('/public/')) || (extname != '' && !is_api_format)
    # Serve static files directly
    response = serve_static_file(path, method: httpMethod)
    return response if response['statusCode'] != 404
  end

  requestTimeEpoch = requestContext['timeEpoch']

  rawQueryString = event['rawQueryString'] || ''
  cookies = event['cookies'] || []

  requestHeaders = event.fetch('headers')
  host = requestHeaders['x-forwarded-host'] || requestHeaders.fetch('host')
  port = requestHeaders.fetch('x-forwarded-port')
  scheme = requestHeaders['cloudfront-forwarded-proto'] || requestHeaders.fetch('x-forwarded-proto')
  client_ip = client_ip_from(http, requestHeaders)

  requestBody = event['body'] || ''
  if event['isBase64Encoded']
    requestBody = Base64.decode64(requestBody)
  end
  requestBodyContent = StringIO.new(requestBody.b)

  # Set environment for Rack application
  # https://github.com/rack/rack/blob/main/SPEC.rdoc
  env = {
    Rack::REQUEST_METHOD => httpMethod,
    Rack::SCRIPT_NAME => RELATIVE_URL_ROOT || '',
    Rack::PATH_INFO => path,
    Rack::QUERY_STRING => rawQueryString,
    Rack::SERVER_NAME => host,
    Rack::SERVER_PORT => port,
    Rack::SERVER_PROTOCOL => protocol,
    'REMOTE_ADDR' => client_ip,

    Rack::RACK_URL_SCHEME => scheme,
    Rack::RACK_INPUT => requestBodyContent,
    Rack::RACK_ERRORS => $stderr,

    # Escape hatch for access to the context and event of Lambda function
    'schengen.client_ip' => client_ip,
    'lambda.context' => context,
    'lambda.event' => event,
  }

  # Add request headers to environment based on Rack specification
  requestHeaders.each_pair do |key, value|
    name = key.upcase.gsub('-', '_')
    header = case name
      when 'CONTENT_TYPE', 'CONTENT_LENGTH'
        name
      else
        "HTTP_#{name}"
    end
    env[header] = value
  end

  # Trust the decoded Lambda event body over forwarded Content-Length headers so
  # Rack/Rails sees the actual request size after API Gateway normalization.
  env['CONTENT_LENGTH'] = requestBody.bytesize.to_s

  if cookies.any?
    env['HTTP_COOKIE'] = cookies.join('; ')
  end

  env['HTTP_X_REQUEST_ID'] ||= context.aws_request_id
  env['HTTP_X_REQUEST_START'] ||= "t=#{requestTimeEpoch}" if requestTimeEpoch

  status, response_headers, response_body = $app.call(env)
  lambda_response(status, response_headers, response_body, head: httpMethod == 'HEAD')
rescue StandardError => exception
  warn "Lambda HTTP error: #{exception.class}: #{exception.message}"
  { 'statusCode' => 500, 'body' => 'Internal Server Error' }
end
