require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SchengenTrack
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0
    Rails.application.routes.default_url_options[:host] = "localhost:3000"
    config.i18n.available_locales = [:en, :de, :es, :tr, :'zh-CN', :hi, :'pt-BR']

    # Disable deprecated secrets.yml loading - we use ENV variables via AppConfig
    config.read_encrypted_secrets = false
    
    config.action_view.field_error_proc = Proc.new { |html_tag, instance| 
      html_tag
    }
    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
