# frozen_string_literal: true

module AnonymousCalculator
  class FirstSave
    Result = Struct.new(:record, :user, :person, keyword_init: true) do
      def success?
        record.persisted?
      end
    end

    def self.call(nationality:, record_class:, attributes:)
      new(nationality:, record_class:, attributes:).call
    end

    def initialize(nationality:, record_class:, attributes:)
      raise ArgumentError, 'unsupported calculator record' unless [Visit, Visa].include?(record_class)

      @nationality = nationality
      @record_class = record_class
      @attributes = attributes
    end

    def call
      user = person = record = nil

      User.transaction do
        user = User.create!(
          guest: true,
          email: "guest_#{SecureRandom.uuid}@example.com",
          password: Devise.friendly_token.first(20),
          first_name: 'Guest',
          last_name: 'User',
          nationality: @nationality
        )
        person = user.people.find_by!(is_primary: true)
        record = person.public_send(association_name).build(@attributes)
        record.visa_type = 'S' if record.is_a?(Visa)
        raise ActiveRecord::Rollback unless record.save
      end

      Result.new(record:, user: record&.persisted? ? user : nil, person: record&.persisted? ? person : nil)
    end

    private

    def association_name
      @record_class == Visit ? :visits : :visas
    end
  end
end
