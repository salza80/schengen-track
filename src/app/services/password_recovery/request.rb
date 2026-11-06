require 'ipaddr'
require 'openssl'

module PasswordRecovery
  class Request
    CLIENT_LIMIT = 10
    CLIENT_PERIOD = 15.minutes
    RECIPIENT_COOLDOWN = 10.minutes
    RECIPIENT_DAILY_LIMIT = 5
    DELIVERY_LIMIT = 100
    DELIVERY_PERIOD = 1.hour
    MAX_EMAIL_BYTES = 320

    class Throttled < StandardError
      attr_reader :retry_after
      def initialize(retry_after)
        @retry_after = retry_after
        super('Too many recovery requests')
      end
    end

    def initialize(email:, client_ip:)
      @email = email.is_a?(String) && email.bytesize <= MAX_EMAIL_BYTES ? email.strip.downcase : nil
      @client_ip = client_ip
    end

    def call
      client = limit('recovery:client', fingerprint('client', client_network), CLIENT_LIMIT, CLIENT_PERIOD)
      raise Throttled, [(client.reset_at - Time.current).ceil, 1].max unless client.allowed?
      return if @email.blank?

      # Reserve quotas atomically, then release database locks before SMTP.
      # Unknown addresses reserve the same recipient buckets as real accounts.
      account = ActiveRecord::Base.transaction do
        recipient = fingerprint('recipient', @email)
        next unless RateLimiters::DatabaseCooldown.claim(scope: 'recovery:cooldown', identifier: recipient, period: RECIPIENT_COOLDOWN)
        next unless limit('recovery:recipient', recipient, RECIPIENT_DAILY_LIMIT, 24.hours).allowed?

        user = User.find_by(email: @email)
        next unless user
        next unless limit('recovery:delivery', 'shared', DELIVERY_LIMIT, DELIVERY_PERIOD).allowed?

        user
      end
      account&.send_reset_password_instructions
      nil
    rescue ActiveRecord::ActiveRecordError, PG::Error => error
      Rails.logger.error("Recovery request store unavailable (#{error.class})")
      raise RateLimiters::DatabaseFixedWindow::Unavailable, 'Rate-limit store unavailable'
    end

    private

    def limit(scope, identifier, maximum, period)
      RateLimiters::DatabaseFixedWindow.new(scope: scope, identifier: identifier, limit: maximum, period: period).call
    end

    def client_network
      address = IPAddr.new(@client_ip.to_s).native
      address.ipv6? ? address.mask(64).to_s : address.to_s
    rescue IPAddr::InvalidAddressError
      'unknown'
    end

    def fingerprint(kind, value)
      key = Rails.application.key_generator.generate_key('password-recovery-abuse', 32)
      OpenSSL::HMAC.hexdigest('SHA256', key, "#{kind}:#{value}")
    end
  end
end
