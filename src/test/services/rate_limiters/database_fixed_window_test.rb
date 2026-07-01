require 'test_helper'

module RateLimiters
  class DatabaseFixedWindowTest < ActiveSupport::TestCase
    test 'increments the current shared database window' do
      first = DatabaseFixedWindow.new(
        scope: 'test',
        identifier: '127.0.0.1',
        limit: 2,
        period: 10.minutes
      ).call

      second = DatabaseFixedWindow.new(
        scope: 'test',
        identifier: '127.0.0.1',
        limit: 2,
        period: 10.minutes
      ).call

      third = DatabaseFixedWindow.new(
        scope: 'test',
        identifier: '127.0.0.1',
        limit: 2,
        period: 10.minutes
      ).call

      assert first.allowed?
      assert second.allowed?
      refute third.allowed?
      assert_equal 0, third.remaining
    end

    test 'deletes expired rows' do
      ApiRateLimit.create!(
        rate_limit_key: 'expired',
        scope: 'test',
        identifier: '127.0.0.1',
        window_start: 2.hours.ago,
        expires_at: 1.hour.ago,
        count: 1
      )
      ApiRateLimit.create!(
        rate_limit_key: 'active',
        scope: 'test',
        identifier: '127.0.0.1',
        window_start: Time.current,
        expires_at: 1.hour.from_now,
        count: 1
      )

      assert_difference('ApiRateLimit.count', -1) do
        ApiRateLimit.delete_expired!
      end

      assert_nil ApiRateLimit.find_by(rate_limit_key: 'expired')
      assert_not_nil ApiRateLimit.find_by(rate_limit_key: 'active')
    end

    test 'allows requests when rate limit table is not migrated yet' do
      limiter = DatabaseFixedWindow.new(
        scope: 'test',
        identifier: '127.0.0.1',
        limit: 2,
        period: 10.minutes
      )
      connection = ActiveRecord::Base.connection
      original_raw_connection = connection.method(:raw_connection)
      original_cleanup_sampled = limiter.method(:cleanup_sampled?)
      missing_table = ActiveRecord::StatementInvalid.new('PG::UndefinedTable: ERROR: relation "api_rate_limits" does not exist')
      fake_raw_connection = Object.new
      fake_raw_connection.define_singleton_method(:exec_params) { |*| raise missing_table }

      connection.define_singleton_method(:raw_connection) { fake_raw_connection }
      limiter.define_singleton_method(:cleanup_sampled?) { false }

      result = limiter.call

      assert result.allowed?
      assert_equal 2, result.remaining
      assert_equal 0, result.count
    ensure
      connection.define_singleton_method(:raw_connection, original_raw_connection) if connection && original_raw_connection
      limiter.define_singleton_method(:cleanup_sampled?, original_cleanup_sampled) if limiter && original_cleanup_sampled
    end
  end
end
