# frozen_string_literal: true

# Loads runtime secrets before Rails initializes. Lambda environment variables
# contain only SSM parameter names, keeping secret values out of CloudFormation
# and Lambda environment configuration.
module SecureEnvironmentLoader
  PARAMETER_ENV_BY_VALUE_ENV = {
    'DB_URL' => 'DB_URL_PARAM',
    'RAILS_MASTER_KEY' => 'RAILS_MASTER_KEY_PARAM',
    'SECRET_KEY_BASE' => 'SECRET_KEY_BASE_PARAM',
    'FACEBOOK_SECRET' => 'FACEBOOK_SECRET_PARAM',
    'BREVO_PASSWORD' => 'BREVO_PASSWORD_PARAM'
  }.freeze

  module_function

  def load!(client: nil)
    requested_parameters = PARAMETER_ENV_BY_VALUE_ENV.each_with_object({}) do |(value_env, parameter_env), requested|
      next if ENV[value_env].to_s != ''

      parameter_name = ENV[parameter_env]
      requested[value_env] = parameter_name if parameter_name.to_s != ''
    end
    return if requested_parameters.empty?

    require 'aws-sdk-ssm'
    client ||= Aws::SSM::Client.new(region: aws_region)
    response = client.get_parameters(
      names: requested_parameters.values.uniq,
      with_decryption: true
    )
    values_by_name = response.parameters.to_h { |parameter| [parameter.name, parameter.value] }
    missing_parameters = requested_parameters.values.select do |name|
      values_by_name[name].to_s == ''
    end
    unless missing_parameters.empty?
      raise "Missing or empty SSM runtime parameters: #{missing_parameters.join(', ')}"
    end

    requested_parameters.each do |value_env, parameter_name|
      ENV[value_env] = values_by_name.fetch(parameter_name)
    end
  end

  def aws_region
    ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
  end
  private_class_method :aws_region
end
