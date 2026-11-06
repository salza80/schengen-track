require 'test_helper'
require 'minitest/mock'

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

    [PG::UndefinedTable, PG::ConnectionBad, ActiveRecord::StatementInvalid,
     ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError].each do |error_class|
      test "rejects requests when the counter fails with #{error_class}" do
        limiter = DatabaseFixedWindow.new(scope: 'test', identifier: '127.0.0.1', limit: 2, period: 10.minutes)
        error = error_class.new('database details must not be exposed')
        fake_connection = Object.new
        fake_connection.define_singleton_method(:exec_params) { |*| raise error }

        limiter.stub(:cleanup_sampled?, false) do
          ActiveRecord::Base.connection.stub(:raw_connection, fake_connection) do
            raised = assert_raises(DatabaseFixedWindow::Unavailable) { limiter.call }
            assert_same error, raised.cause
            assert_equal 'Rate-limit store unavailable', raised.message
          end
        end
      end
    end

    test 'cleanup failure cannot authorize a request' do
      limiter = DatabaseFixedWindow.new(scope: 'test', identifier: '127.0.0.1', limit: 2, period: 10.minutes)
      limiter.stub(:cleanup_sampled?, true) do
        ApiRateLimit.stub(:delete_expired!, -> { raise PG::UndefinedTable, 'missing table' }) do
          assert_raises(DatabaseFixedWindow::Unavailable) { limiter.call }
        end
      end
    end

    test 'unexpected programming errors are not converted to store outages' do
      limiter = DatabaseFixedWindow.new(scope: 'test', identifier: '127.0.0.1', limit: 2, period: 10.minutes)
      limiter.stub(:cleanup_sampled?, -> { raise ArgumentError, 'invalid configuration' }) do
        assert_raises(ArgumentError) { limiter.call }
      end
    end
  end
end
