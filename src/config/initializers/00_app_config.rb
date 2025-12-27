# frozen_string_literal: true

# Application configuration wrapper for environment variables
# Provides type safety and single source of truth for all config access
class AppConfig
  class << self
    def secret_key_base
      ENV['SECRET_KEY_BASE']
    end

    def facebook_id
      ENV['FACEBOOK_ID']
    end

    def facebook_secret
      ENV['FACEBOOK_SECRET']
    end

    def facebook_callback_url
      ENV['FACEBOOK_CALLBACK_URL']
    end

    def aws_access_key_id
      ENV['AWS_ACCESS_KEY_ID']
    end

    def aws_secret_key
      ENV['AWS_SECRET_KEY']
    end

    def brevo_login
      ENV['BREVO_LOGIN']
    end

    def brevo_password
      ENV['BREVO_PASSWORD']
    end

    def task_password
      ENV['TASK_PASSWORD']
    end
  end
end
