require 'test_helper'
require 'minitest/mock'

class AppConfigTest < ActiveSupport::TestCase
  setup do
    @original_ga_api_secret = ENV['GA_API_SECRET']
    @original_ga_api_secret_param = ENV['GA_API_SECRET_PARAM']
    ENV.delete('GA_API_SECRET')
    ENV['GA_API_SECRET_PARAM'] = '/scheng/test/ga_api_secret'
    reset_ssm_parameter_cache
  end

  teardown do
    if @original_ga_api_secret.nil?
      ENV.delete('GA_API_SECRET')
    else
      ENV['GA_API_SECRET'] = @original_ga_api_secret
    end

    if @original_ga_api_secret_param.nil?
      ENV.delete('GA_API_SECRET_PARAM')
    else
      ENV['GA_API_SECRET_PARAM'] = @original_ga_api_secret_param
    end

    reset_ssm_parameter_cache
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

  private

  def reset_ssm_parameter_cache
    return unless AppConfig.instance_variable_defined?(:@ssm_parameter_cache)

    AppConfig.remove_instance_variable(:@ssm_parameter_cache)
  end

  def response_with_parameter(value)
    parameter = Struct.new(:value).new(value)
    Struct.new(:parameter).new(parameter)
  end
end
