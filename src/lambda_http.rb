require 'json'
require 'rack'
require 'base64'

$app ||= Rack::Builder.parse_file("#{__dir__}/config.ru").first

RELATIVE_URL_ROOT = ENV['RAILS_RELATIVE_URL_ROOT']

def serve_static_file(path)
  app = Rack::Builder.new do
    use Rack::Static, root: 'public', urls: [''], mime_types: { ".ico" => "image/x-icon" }
    run lambda { |env|
      if env['REQUEST_METHOD'] == 'GET'
        Rack::Static.new(
          lambda { |inner_env| [404, {}, ['Not Found']] },
          root: 'public',
          urls: ['/assets']
        ).call(env)
      else
        [405, { 'Content-Type' => 'text/plain' }, ['Method Not Allowed']]
      end
    }
  end

  response = app.call('PATH_INFO' => path, 'REQUEST_METHOD' => 'GET')
  content = ''
  response[2].each { |part| content << part }

  isBase64 = is_binary_content?(response[1])
  content = Base64.strict_encode64(content) if isBase64
  {
    'statusCode' => response[0],
    'headers' => response[1],
    'body' => content,
    'isBase64Encoded' => isBase64
  }
end

# Function to determine if content type is binary
def is_binary_content?(headers)
  content_type = headers['Content-Type']

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

  # In input format 2.0, the path always contains a stage
  stage = requestContext['stage'] || '$default'
  if stage != '$default'
    path.sub!(/\A\/#{stage}/, '')
  end

  path = event['requestContext']['http']['path']
  # Check if the request is for a static file
  if path.start_with?('/assets/') || path.start_with?('/public/') || File.extname(path) != ''
    # Serve static files directly
    response = serve_static_file(path)
    return response if response['statusCode'] != 404
  end

  requestTimeEpoch = requestContext['timeEpoch']

  rawQueryString = event['rawQueryString']
  cookies = event['cookies'] || []

  requestHeaders = event.fetch('headers')
  host = requestHeaders['x-forwarded-host'] || requestHeaders.fetch('host')
  port = requestHeaders.fetch('x-forwarded-port')
  scheme = requestHeaders['cloudfront-forwarded-proto'] || requestHeaders.fetch('x-forwarded-proto')

  requestBody = event['body'] || ''
  if event['isBase64Encoded']
    requestBody = Base64.decode64(requestBody)
  end
  requestBodyContent = StringIO.new(requestBody)

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

    Rack::RACK_VERSION => Rack::VERSION,
    Rack::RACK_URL_SCHEME => scheme,
    Rack::RACK_INPUT => requestBodyContent,
    Rack::RACK_ERRORS => $stderr,

    # Escape hatch for access to the context and event of Lambda function
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

  env['CONTENT_LENGTH'] ||= requestBodyContent.size.to_s

  if cookies.any?
    env['HTTP_COOKIE'] = cookies.join('; ')
  end

  env['HTTP_X_REQUEST_ID'] ||= context.aws_request_id
  env['HTTP_X_REQUEST_START'] ||= "t=#{requestTimeEpoch}" if requestTimeEpoch

  begin
    # Execute Rack application and get response
    status, responseHeaders, responseBody = $app.call(env)

    # Build response body
    responseBodyContent = ''

    # if responseBody.respond_to?(:each)
    #   responseBody.each do |item|
    #     responseBodyContent << item if item
    #   end
    # end
    responseBodyContent = if responseBody.respond_to?(:each)
      if responseBody.respond_to?(:binmode)
        # If responseBody supports binmode, set it to binary mode
        responseBody.binmode
      end
    
      # If the content is binary, return it directly
      if responseBody.respond_to?(:read)
        responseBody.read
      else
        # If the content is not binary, concatenate as a string
        responseBody.each.to_a.join unless responseBodyContent.nil?
      end
    end    

    if responseBody.respond_to?(:close)
      responseBody.close
    end

    # Generate response conforming to HTTP API output format 2.0
    # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#http-api-develop-integrations-lambda.v2
    response = {
      'statusCode' => status,
      'body' => responseBodyContent
    }

    # If 'Set-Cookie' response header is present, split it and set as 'cookies' response field
    responseCookies = []
    if setCookie = responseHeaders&.delete('Set-Cookie')
      if setCookie.is_a?(::Array)
        responseCookies = setCookie
      elsif setCookie.is_a?(::String)
        responseCookies = setCookie.split("\n")
      end
    end
    if !responseCookies.empty?
      response['cookies'] = responseCookies
    end

    # Set response headers as 'headers' response field
    unifiedResponseHeaders = {}
    responseHeaders&.each { |key, value|
      if value.is_a?(::Array)
        unifiedResponseHeaders[key] = value.join(',')
      elsif value.is_a?(::String)
        unifiedResponseHeaders[key] = value.split("\n").join(',')
      end
    }
    if !unifiedResponseHeaders.empty?
      response['headers'] = unifiedResponseHeaders
    end

    return response

  rescue Exception => exception
    return {
      'statusCode' => 500,
      # For debug purpose only. It is not recommended to include error messages in the response body
      'body' => exception.message
    }
  end
end