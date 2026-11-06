require 'test_helper'
require 'minitest/mock'

module RateLimiters
  class DatabaseCooldownTest < ActiveSupport::TestCase
    test 'cooldown spans fixed-window boundaries and denials do not extend it' do
      travel_to Time.utc(2026, 11, 6, 12, 9, 59) do
        assert DatabaseCooldown.claim(scope: 'test:cooldown', identifier: 'sample', period: 10.minutes)
        travel 2.seconds
        refute DatabaseCooldown.claim(scope: 'test:cooldown', identifier: 'sample', period: 10.minutes)
        travel 9.minutes + 58.seconds
        assert DatabaseCooldown.claim(scope: 'test:cooldown', identifier: 'sample', period: 10.minutes)
      end
    end

    test 'missing cooldown storage raises instead of authorizing delivery' do
      raw = Object.new
      raw.define_singleton_method(:exec_params) { |*| raise PG::UndefinedTable, 'missing table' }
      ActiveRecord::Base.connection.stub(:raw_connection, raw) do
        assert_raises(DatabaseFixedWindow::Unavailable) do
          DatabaseCooldown.claim(scope: 'test:cooldown', identifier: 'sample', period: 10.minutes)
        end
      end
    end
  end
end
