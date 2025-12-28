# Load secrets from secrets.yml into ENV for development and test environments
# This allows us to use ENV vars consistently across all environments while
# keeping development secrets in a local YAML file (not committed to production)

unless Rails.env.production?
  secrets_file = Rails.root.join('config', 'secrets.yml')
  
  if File.exist?(secrets_file)
    secrets = YAML.safe_load_file(secrets_file, aliases: true)[Rails.env]
    
    secrets.each do |key, value|
      ENV[key.upcase] ||= value.to_s
    end
  end
end
