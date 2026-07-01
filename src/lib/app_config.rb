# frozen_string_literal: true

# Application configuration wrapper for environment variables
# Provides type safety and single source of truth for all config access
class AppConfig
  class << self
    def secret_key_base
      # During asset precompilation, allow dummy value
      ENV['SECRET_KEY_BASE'] || ENV['SECRET_KEY_BASE_DUMMY'] || 
        (raise "Missing required environment variable: SECRET_KEY_BASE")
    end

    def facebook_id
      fetch_optional('FACEBOOK_ID')
    end

    def facebook_secret
      fetch_optional('FACEBOOK_SECRET')
    end

    def facebook_callback_url
      fetch_optional('FACEBOOK_CALLBACK_URL')
    end

    def aws_access_key_id
      fetch_optional('AWS_ACCESS_KEY_ID')
    end

    def aws_secret_key
      fetch_optional('AWS_SECRET_KEY')
    end

    def brevo_login
      fetch_optional('BREVO_LOGIN')
    end

    def brevo_password
      fetch_optional('BREVO_PASSWORD')
    end

    def task_password
      fetch_optional('TASK_PASSWORD')
    end

    def google_analytics_measurement_id
      fetch_optional('GA_MEASUREMENT_ID') || 'G-E9CCZDHLJF'
    end

    def google_analytics_api_secret
      fetch_optional('GA_API_SECRET') || fetch_ssm_parameter('GA_API_SECRET_PARAM')
    end

    private

    def fetch_required(key)
      value = ENV[key]
      if value.nil? || value.empty?
        raise "Missing required environment variable: #{key}"
      end
      value
    end

    def fetch_optional(key)
      ENV[key]
    end

    def fetch_ssm_parameter(env_key)
      param_name = ENV[env_key]
      return if param_name.nil? || param_name.empty?

      @ssm_parameter_cache ||= {}
      return @ssm_parameter_cache[param_name] if @ssm_parameter_cache.key?(param_name)

      require 'aws-sdk-ssm'

      response = Aws::SSM::Client.new(
        region: ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
      ).get_parameter(name: param_name, with_decryption: true)

      @ssm_parameter_cache[param_name] = response.parameter.value
    rescue StandardError => e
      Rails.logger.warn("Unable to load SSM parameter #{param_name}: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end
  end
end
