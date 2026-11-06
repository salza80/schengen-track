# frozen_string_literal: true

module GuestCalculations
  class Capacity
    class Exceeded < StandardError; end
    MAX_PEOPLE = 20
    MAX_RECORDS = 500

    def self.with_space_for(record)
      owner = record.is_a?(Person) ? record.user : record.person.user
      return yield unless owner.is_guest?

      # Every guest allocation locks the same parent, including allocations
      # to different travelers. Count and insert must share this transaction.
      owner.with_lock do
        people = Person.where(user_id: owner.id)
        full = if record.is_a?(Person)
                 people.count >= MAX_PEOPLE
               else
                 Visit.where(person_id: people.select(:id)).count +
                   Visa.where(person_id: people.select(:id)).count >= MAX_RECORDS
               end
        raise Exceeded if full

        yield
      end
    end
  end
end
