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
  end
end
