# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class DatabaseUrlLoaderTest < ActiveSupport::TestCase
  setup do
    @original_db_url = ENV['DB_URL']
    @original_db_url_param = ENV['DB_URL_PARAM']
  end

  teardown do
    restore_env('DB_URL', @original_db_url)
    restore_env('DB_URL_PARAM', @original_db_url_param)
  end

  test 'loads and decrypts the configured database URL parameter' do
    ENV.delete('DB_URL')
    ENV['DB_URL_PARAM'] = '/scheng/test/db_pooler_url'
    response = Struct.new(:parameter).new(Struct.new(:value).new('postgresql://pooled.example/test'))
    client = Minitest::Mock.new
    client.expect(
      :get_parameter,
      response,
      [],
      name: '/scheng/test/db_pooler_url',
      with_decryption: true
    )

    DatabaseUrlLoader.load!(client: client)

    assert_equal 'postgresql://pooled.example/test', ENV['DB_URL']
    client.verify
  end

  test 'keeps an explicitly configured database URL' do
    ENV['DB_URL'] = 'postgresql://direct.example/test'
    ENV['DB_URL_PARAM'] = '/scheng/test/db_pooler_url'

    assert_equal 'postgresql://direct.example/test', DatabaseUrlLoader.load!
  end

  private

  def restore_env(key, value)
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end
