require 'test_helper'
require 'timeout'

module RateLimiters
  class DatabaseCooldownConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup { @scope = "test:concurrent-cooldown:#{SecureRandom.hex(8)}" }
    teardown { ApiRateLimit.where(scope: @scope).delete_all }

    test 'concurrent recipient reservations have exactly one winner' do
      ready, start, results = Queue.new, Queue.new, Queue.new
      workers = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            results << DatabaseCooldown.claim(scope: @scope, identifier: 'sample', period: 10.minutes)
          rescue StandardError => error
            results << error
          end
        end
      end
      Timeout.timeout(10) do
        2.times { ready.pop }
        2.times { start << true }
        workers.each(&:value)
      end
      outcomes = 2.times.map { results.pop }
      assert_equal 1, outcomes.count(true), outcomes.inspect
      assert_equal 1, outcomes.count(false), outcomes.inspect
    ensure
      workers&.each { |worker| worker.kill if worker.alive?; worker.join }
    end
  end
end
