module AgentCalculations
  class Create
    MAX_TRIPS = 50
    MAX_VISAS = 20

    Result = Struct.new(:success?, :payload, :errors, keyword_init: true)

    def initialize(params:, url_helpers:, base_url:)
      @params = params
      @url_helpers = url_helpers
      @base_url = base_url
      @errors = []
    end

    def call
      validate_required_params
      return failure if @errors.any?

      user = nil
      person = nil

      ActiveRecord::Base.transaction do
        user = create_guest_user!
        person = user.people.where(is_primary: true).first || user.people.first
        create_visits!(person)
        create_visas!(person)
      end

      success(payload_for(user, person))
    rescue ActiveRecord::RecordInvalid => e
      @errors << { field: e.record.class.name.underscore, message: e.record.errors.full_messages.to_sentence }
      failure
    rescue ArgumentError => e
      @errors << { field: 'base', message: e.message }
      failure
    end

    private

    attr_reader :params, :url_helpers, :base_url

    def validate_required_params
      add_error(code: 'missing_user', field: 'user', message: 'User details are required.') unless user_params.present?
      add_error(
        code: 'missing_nationality',
        field: 'user.nationality',
        message: 'User nationality is required as an uppercase ISO 3166-1 alpha-2 country code.'
      ) if user_params.present? && user_params['nationality'].blank?
      add_error(code: 'missing_trips', field: 'trips', message: 'At least one trip is required.') unless trips.any?

      if trips.length > MAX_TRIPS
        add_error(
          code: 'too_many_trips',
          field: 'trips',
          message: "Too many trips. Maximum is #{MAX_TRIPS}.",
          limit: MAX_TRIPS,
          received: trips.length
        )
      end

      if visas.length > MAX_VISAS
        add_error(
          code: 'too_many_visas',
          field: 'visas',
          message: "Too many visas. Maximum is #{MAX_VISAS}.",
          limit: MAX_VISAS,
          received: visas.length
        )
      end
    end

    def create_guest_user!
      nationality = find_country!(user_params['nationality'], 'user.nationality')
      first_name = user_params['first_name'].presence || 'Guest'
      last_name = user_params['last_name'].presence || 'Traveler'

      User.create!(
        guest: true,
        email: guest_email,
        password: Devise.friendly_token[0, 20],
        first_name: first_name,
        last_name: last_name,
        nationality: nationality
      )
    end

    def create_visits!(person)
      trips.each_with_index do |trip, index|
        country = find_country!(trip['country_code'], "trips[#{index}].country_code")
        person.visits.create!(
          country: country,
          entry_date: parse_date!(trip['entry_date'], "trips[#{index}].entry_date"),
          exit_date: parse_date!(trip['exit_date'], "trips[#{index}].exit_date")
        )
      end
    end

    def create_visas!(person)
      visas.each_with_index do |visa, index|
        person.visas.create!(
          visa_type: visa['visa_type'].presence || 'S',
          start_date: parse_date!(visa['start_date'], "visas[#{index}].start_date"),
          end_date: parse_date!(visa['end_date'], "visas[#{index}].end_date"),
          no_entries: visa['no_entries'].presence || 0
        )
      end
    end

    def payload_for(user, person)
      calc = Schengen::Days::Calculator.new(person)
      days = calc.calculated_days
      final_day = final_calculated_day(days, person)
      token = user.signed_id(purpose: :agent_calculation, expires_in: 30.days)
      view_url = "#{base_url}#{calendar_path_for(person, token)}"

      days_used = final_day&.schengen_days_count || 0
      days_remaining = final_day&.max_remaining_days || [90 - days_used, 0].max
      overstay_days = days.map(&:overstay_days).compact.max || 0

      {
        calculation_id: "guest_#{user.id}",
        status: status_for(calc, days_used),
        days_used: days_used,
        days_remaining: days_remaining,
        overstay: calc.schengen_overstay?,
        overstay_days: overstay_days,
        next_allowed_entry_date: calc.next_entry_days.first&.the_date&.iso8601,
        summary: summary_for(calc, days_used, days_remaining, overstay_days),
        user_message: user_message_for(days_used, days_remaining, overstay_days, view_url, calc),
        web_url: view_url,
        claim_url: view_url,
        person: {
          first_name: person.first_name,
          last_name: person.last_name,
          nationality: person.nationality_with_default.country_code
        },
        trips: person.visits.map { |visit| visit_payload(visit) }
      }
    end

    def final_calculated_day(days, person)
      last_exit_date = person.visits.maximum(:exit_date)
      days.find { |day| day.the_date == last_exit_date } || days.max_by(&:the_date)
    end

    def calendar_path_for(_person, token)
      url_helpers.days_path(locale: I18n.default_locale, guest_calculation: token)
    end

    def status_for(calc, days_used)
      return 'overstay' if calc.schengen_overstay?
      return 'warning' if days_used >= 80

      'safe'
    end

    def summary_for(calc, days_used, days_remaining, overstay_days)
      if calc.schengen_overstay?
        "The planned trips exceed the Schengen allowance by #{overstay_days} #{'day'.pluralize(overstay_days)}."
      elsif days_remaining.zero?
        'The planned trips use all 90 Schengen days.'
      else
        "The planned trips use #{days_used} Schengen #{'day'.pluralize(days_used)}, with #{days_remaining} #{'day'.pluralize(days_remaining)} remaining."
      end
    end

    def user_message_for(days_used, days_remaining, overstay_days, view_url, calc)
      result = if calc.schengen_overstay?
                 "Your planned trips appear to exceed the Schengen allowance by #{overstay_days} #{'day'.pluralize(overstay_days)}."
               elsif days_remaining.zero?
                 'Your planned trips appear to use all 90 Schengen days.'
               else
                 "Your planned trips appear to use #{days_used} Schengen #{'day'.pluralize(days_used)}, leaving #{days_remaining} #{'day'.pluralize(days_remaining)}."
               end

      "#{result} You can view, review, edit, or save the calculation at #{view_url}"
    end

    def visit_payload(visit)
      {
        country_code: visit.country.country_code,
        country_name: visit.country.name,
        entry_date: visit.entry_date.iso8601,
        exit_date: visit.exit_date.iso8601,
        schengen: visit.schengen?,
        days: visit.no_days
      }
    end

    def user_params
      params['user'] || {}
    end

    def trips
      Array(params['trips'])
    end

    def visas
      Array(params['visas'])
    end

    def find_country!(code, field)
      country = Country.find_by(country_code: code.to_s.upcase)
      return country if country

      raise ArgumentError, "#{field} is not a supported country code"
    end

    def parse_date!(value, field)
      raise ArgumentError, "#{field} is required" if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise ArgumentError, "#{field} must be an ISO 8601 date"
    end

    def guest_email
      "agent_guest_#{Time.now.to_i}_#{SecureRandom.hex(6)}@example.com"
    end

    def add_error(error = nil, **attributes)
      error ||= attributes
      @errors << error
    end

    def success(payload)
      Result.new(success?: true, payload: payload, errors: [])
    end

    def failure
      Result.new(success?: false, payload: nil, errors: @errors)
    end
  end
end
