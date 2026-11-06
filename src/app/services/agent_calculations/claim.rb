require 'securerandom'

module AgentCalculations
  class Claim
    class Unavailable < StandardError; end
    class TooLarge < StandardError; end
    MAX_PEOPLE = GuestCalculations::Capacity::MAX_PEOPLE
    MAX_RECORDS = GuestCalculations::Capacity::MAX_RECORDS
    Result = Struct.new(:user, :person, keyword_init: true)

    def self.find_available_source!(token)
      raise Unavailable unless token.is_a?(String) && token.bytesize <= 2048

      user = User.find_signed!(token, purpose: :agent_calculation)
      raise Unavailable unless user.is_guest? && user.calculation_claimed_at.nil?

      user
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      raise Unavailable
    end

    def initialize(token:, account:, guest:)
      @token, @account, @guest = token, account, guest
    end

    def call
      User.transaction do
        source = self.class.find_available_source!(@token)
        # Importing an existing guest must see a stable capacity snapshot.
        # Use the same lock as ordinary guest inserts, in a consistent order.
        User.where(id: [source.id, @guest&.id].compact).order(:id).lock.load
        source.reload
        raise Unavailable if source.calculation_claimed_at.present?
        validate_import_size!(source)

        if @account
          target = @account
          person = append_people(source, target)
        else
          # Never keep writing into an identity that another bearer or an old
          # browser session can still access. Preserve existing travelers in
          # the new private guest rather than silently replacing their data.
          profile = @guest || source
          primary_profile = profile.people.find_by(is_primary: true) || profile.people.first || profile
          target = User.create!(
            guest: true, email: "guest_#{SecureRandom.hex(16)}@example.com",
            password: Devise.friendly_token[0, 20],
            first_name: primary_profile.first_name, last_name: primary_profile.last_name,
            nationality: primary_profile.nationality || profile.nationality
          )
          target.copy_from(profile)
          person = profile == source ? target.people.find_by!(is_primary: true) : append_people(source, target)
        end

        source.update!(calculation_claimed_at: Time.current)
        Result.new(user: target, person: person)
      end
    end

    private

    def validate_import_size!(source)
      sources = [source]
      sources << @guest if @guest && !@account && @guest != source
      people = Person.where(user_id: sources.map(&:id))
      records = Visit.where(person_id: people.select(:id)).count + Visa.where(person_id: people.select(:id)).count
      raise TooLarge if people.count > MAX_PEOPLE || records > MAX_RECORDS
    end

    def append_people(source, target)
      selected = nil
      source.people.order(is_primary: :desc, id: :asc).each do |original|
        person = target.people.create!(
          first_name: original.first_name, last_name: original.last_name,
          nationality_id: original.nationality_id, is_primary: false
        )
        selected ||= person
        [original.visits, original.visas].each do |records|
          records.each { |record| record.dup.tap { |copy| copy.person = person }.save! }
        end
      end
      raise Unavailable unless selected

      selected
    end
  end
end
