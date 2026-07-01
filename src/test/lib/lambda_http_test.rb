require 'test_helper'
require Rails.root.join('lambda_http')

class LambdaHttpTest < ActiveSupport::TestCase
  test 'client ip prefers CloudFront viewer header over forwarded chain' do
    http = { 'sourceIp' => '198.51.100.10' }
    headers = {
      'x-schengen-client-ip' => '203.0.113.42',
      'x-forwarded-for' => '192.0.2.99, 203.0.113.42, 198.51.100.10'
    }

    assert_equal '203.0.113.42', client_ip_from(http, headers)
  end

  test 'client ip uses first forwarded address from CloudFront chain' do
    http = { 'sourceIp' => '198.51.100.10' }
    headers = { 'x-forwarded-for' => '203.0.113.42, 198.51.100.10' }

    assert_equal '203.0.113.42', client_ip_from(http, headers)
  end

  test 'client ip falls back to API Gateway source ip' do
    http = { 'sourceIp' => '198.51.100.10' }

    assert_equal '198.51.100.10', client_ip_from(http, {})
  end
end
