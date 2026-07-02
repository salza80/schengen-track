require 'test_helper'
require 'minitest/mock'

class AppConfigTest < ActiveSupport::TestCase
  setup do
    @original_ga_measurement_id = ENV['GA_MEASUREMENT_ID']
    @original_ga_api_secret = ENV['GA_API_SECRET']
    @original_ga_api_secret_param = ENV['GA_API_SECRET_PARAM']
    @original_cloudfront_origin_auth_header = ENV['CLOUDFRONT_ORIGIN_AUTH_HEADER']
    @original_cloudfront_origin_auth_param = ENV['CLOUDFRONT_ORIGIN_AUTH_PARAM']
    @original_schengen_agent_auth_header = ENV['SCHENGEN_AGENT_AUTH_HEADER']
    @original_schengen_agent_auth_param = ENV['SCHENGEN_AGENT_AUTH_PARAM']
    ENV.delete('GA_MEASUREMENT_ID')
    ENV.delete('GA_API_SECRET')
    ENV['GA_API_SECRET_PARAM'] = '/scheng/test/ga_api_secret'
    ENV.delete('CLOUDFRONT_ORIGIN_AUTH_HEADER')
    ENV.delete('CLOUDFRONT_ORIGIN_AUTH_PARAM')
    ENV.delete('SCHENGEN_AGENT_AUTH_HEADER')
    ENV.delete('SCHENGEN_AGENT_AUTH_PARAM')
    reset_ssm_parameter_cache
  end

  teardown do
    restore_env('GA_MEASUREMENT_ID', @original_ga_measurement_id)
    restore_env('GA_API_SECRET', @original_ga_api_secret)
    restore_env('GA_API_SECRET_PARAM', @original_ga_api_secret_param)
    restore_env('CLOUDFRONT_ORIGIN_AUTH_HEADER', @original_cloudfront_origin_auth_header)
    restore_env('CLOUDFRONT_ORIGIN_AUTH_PARAM', @original_cloudfront_origin_auth_param)
    restore_env('SCHENGEN_AGENT_AUTH_HEADER', @original_schengen_agent_auth_header)
    restore_env('SCHENGEN_AGENT_AUTH_PARAM', @original_schengen_agent_auth_param)

    reset_ssm_parameter_cache
  end

  test 'blank measurement id falls back to the default' do
    ENV['GA_MEASUREMENT_ID'] = ''

    assert_equal 'G-E9CCZDHLJF', AppConfig.google_analytics_measurement_id
  end

  test 'blank api secret falls back to SSM parameter lookup' do
    require 'aws-sdk-ssm'

    ENV['GA_API_SECRET'] = ''

    calls = 0
    response = ->(value) { response_with_parameter(value) }
    client = Object.new
    client.define_singleton_method(:get_parameter) do |name:, with_decryption:|
      calls += 1
      response.call('measurement-secret')
    end

    Aws::SSM::Client.stub(:new, client) do
      assert_equal 'measurement-secret', AppConfig.google_analytics_api_secret
    end

    assert_equal 1, calls
  end

  test 'does not cache nil when SSM parameter lookup fails' do
    require 'aws-sdk-ssm'

    calls = 0
    response = ->(value) { response_with_parameter(value) }
    client = Object.new
    client.define_singleton_method(:get_parameter) do |name:, with_decryption:|
      calls += 1
      raise 'temporary failure' if calls == 1

      response.call('measurement-secret')
    end

    Aws::SSM::Client.stub(:new, client) do
      assert_nil AppConfig.google_analytics_api_secret
      assert_equal 'measurement-secret', AppConfig.google_analytics_api_secret
    end

    assert_equal 2, calls
  end

  test 'caches successful SSM parameter lookup' do
    require 'aws-sdk-ssm'

    calls = 0
    response = ->(value) { response_with_parameter(value) }
    client = Object.new
    client.define_singleton_method(:get_parameter) do |name:, with_decryption:|
      calls += 1
      response.call('measurement-secret')
    end

    Aws::SSM::Client.stub(:new, client) do
      assert_equal 'measurement-secret', AppConfig.google_analytics_api_secret
      assert_equal 'measurement-secret', AppConfig.google_analytics_api_secret
    end

    assert_equal 1, calls
  end

  test 'shared auth headers read configured SSM parameters' do
    require 'aws-sdk-ssm'

    ENV['CLOUDFRONT_ORIGIN_AUTH_PARAM'] = '/scheng/test/cloudfront_origin_auth_header'
    ENV['SCHENGEN_AGENT_AUTH_PARAM'] = '/scheng/test/schengen_agent_auth_header'
    values = {
      '/scheng/test/cloudfront_origin_auth_header' => 'cloudfront-secret',
      '/scheng/test/schengen_agent_auth_header' => 'agent-secret'
    }
    requests = []
    response = ->(value) { response_with_parameter(value) }
    client = Object.new
    client.define_singleton_method(:get_parameter) do |name:, with_decryption:|
      requests << { name: name, with_decryption: with_decryption }
      response.call(values.fetch(name))
    end

    Aws::SSM::Client.stub(:new, client) do
      assert_equal 'cloudfront-secret', AppConfig.cloudfront_origin_auth_header
      assert_equal 'agent-secret', AppConfig.schengen_agent_auth_header
    end

    assert_equal [
      { name: '/scheng/test/cloudfront_origin_auth_header', with_decryption: true },
      { name: '/scheng/test/schengen_agent_auth_header', with_decryption: true }
    ], requests
  end

  private

  def restore_env(key, value)
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
  end

  def reset_ssm_parameter_cache
    return unless AppConfig.instance_variable_defined?(:@ssm_parameter_cache)

    AppConfig.remove_instance_variable(:@ssm_parameter_cache)
  end

  def response_with_parameter(value)
    parameter = Struct.new(:value).new(value)
    Struct.new(:parameter).new(parameter)
  end
end
