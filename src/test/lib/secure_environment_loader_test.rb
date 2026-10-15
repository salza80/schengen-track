# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class SecureEnvironmentLoaderTest < ActiveSupport::TestCase
  ENV_KEYS = SecureEnvironmentLoader::PARAMETER_ENV_BY_VALUE_ENV.to_a.flatten.freeze

  setup do
    @original_env = ENV_KEYS.to_h { |key| [key, ENV[key]] }
    ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    @original_env.each { |key, value| restore_env(key, value) }
  end

  test 'loads and decrypts configured runtime parameters in one request' do
    ENV['DB_URL_PARAM'] = '/scheng/test/secrets/db_pooler_url'
    ENV['SECRET_KEY_BASE_PARAM'] = '/scheng/test/secrets/secret_key_base'
    response = Struct.new(:parameters).new([
      parameter('/scheng/test/secrets/secret_key_base', 'secret-base'),
      parameter('/scheng/test/secrets/db_pooler_url', 'postgresql://pooled.example/test')
    ])
    client = Minitest::Mock.new
    client.expect(
      :get_parameters,
      response,
      [],
      names: ['/scheng/test/secrets/db_pooler_url', '/scheng/test/secrets/secret_key_base'],
      with_decryption: true
    )

    SecureEnvironmentLoader.load!(client: client)

    assert_equal 'postgresql://pooled.example/test', ENV['DB_URL']
    assert_equal 'secret-base', ENV['SECRET_KEY_BASE']
    client.verify
  end

  test 'keeps explicit values and only requests missing values' do
    ENV['DB_URL'] = 'postgresql://direct.example/test'
    ENV['DB_URL_PARAM'] = '/scheng/test/secrets/db_pooler_url'
    ENV['FACEBOOK_SECRET_PARAM'] = '/scheng/test/secrets/facebook_secret'
    response = Struct.new(:parameters).new([
      parameter('/scheng/test/secrets/facebook_secret', 'facebook-secret')
    ])
    client = Minitest::Mock.new
    client.expect(
      :get_parameters,
      response,
      [],
      names: ['/scheng/test/secrets/facebook_secret'],
      with_decryption: true
    )

    SecureEnvironmentLoader.load!(client: client)

    assert_equal 'postgresql://direct.example/test', ENV['DB_URL']
    assert_equal 'facebook-secret', ENV['FACEBOOK_SECRET']
    client.verify
  end

  test 'fails boot when a configured runtime parameter is missing' do
    ENV['FACEBOOK_SECRET_PARAM'] = '/scheng/test/secrets/facebook_secret'
    response = Struct.new(:parameters).new([])
    client = Minitest::Mock.new
    client.expect(
      :get_parameters,
      response,
      [],
      names: ['/scheng/test/secrets/facebook_secret'],
      with_decryption: true
    )

    error = assert_raises(RuntimeError) do
      SecureEnvironmentLoader.load!(client: client)
    end

    assert_includes error.message, '/scheng/test/secrets/facebook_secret'
    client.verify
  end

  private

  def parameter(name, value)
    Struct.new(:name, :value).new(name, value)
  end

  def restore_env(key, value)
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end
