# frozen_string_literal: true

# Loads the database URL before Rails initializes Active Record. Lambda
# environments contain only an SSM parameter name, keeping database credentials
# out of CloudFormation and Lambda environment configuration.
module DatabaseUrlLoader
  module_function

  def load!(client: nil)
    return ENV['DB_URL'] if ENV['DB_URL'].to_s != ''

    parameter_name = ENV['DB_URL_PARAM']
    return if parameter_name.to_s == ''

    require 'aws-sdk-ssm'
    client ||= Aws::SSM::Client.new(region: aws_region)
    value = client.get_parameter(name: parameter_name, with_decryption: true).parameter.value
    raise "SSM database URL parameter is empty: #{parameter_name}" if value.to_s == ''

    ENV['DB_URL'] = value
  end

  def aws_region
    ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
  end
  private_class_method :aws_region
end
