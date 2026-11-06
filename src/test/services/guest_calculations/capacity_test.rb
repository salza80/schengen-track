require 'test_helper'
require 'timeout'

module GuestCalculations
  class CapacityTest < ActiveSupport::TestCase
    # Separate connections must see committed parent rows to exercise row locks.
    self.use_transactional_tests = false

    setup do
      @guest = User.create!(guest: true, email: "capacity_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                            first_name: 'Guest', last_name: 'Traveler', nationality: countries(:India))
    end

    teardown do
      people = Person.where(user_id: @guest.id)
      Visit.where(person_id: people.select(:id)).delete_all
      Visa.where(person_id: people.select(:id)).delete_all
      people.delete_all
      @guest.destroy!
    end

    test 'concurrent allocations across travelers cannot exceed the combined guest capacity' do
      people = [@guest.people.first, @guest.people.create!(first_name: 'Other', nationality: countries(:India))]
      previous_limit = Capacity::MAX_RECORDS
      Capacity.send(:remove_const, :MAX_RECORDS)
      Capacity.const_set(:MAX_RECORDS, 1)
      ready, start, results = Queue.new, Queue.new, Queue.new
      country_id = countries(:Germany).id
      workers = people.map do |person|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            Visit.create!(person_id: person.id, country_id: country_id,
                          entry_date: '2027-10-01', exit_date: '2027-10-05')
            results << :saved
          rescue Capacity::Exceeded
            results << :limited
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
      assert_equal 1, outcomes.count(:saved), outcomes.inspect
      assert_equal 1, outcomes.count(:limited), outcomes.inspect
      assert_equal 1, Visit.where(person_id: people.map(&:id)).count
    ensure
      workers&.each { |worker| worker.kill if worker.alive?; worker.join }
      if previous_limit
        Capacity.send(:remove_const, :MAX_RECORDS)
        Capacity.const_set(:MAX_RECORDS, previous_limit)
      end
    end
  end
end
