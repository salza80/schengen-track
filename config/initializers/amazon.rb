Amazon::Ecs.configure do |options|
  options[:AWS_access_key_id] = Rails.application.secrets.aws_access_key_id
  options[:AWS_secret_key] =  Rails.application.secrets.aws_secret_key
  # options[:associate_tag] = ENV['AWS_ASSOCIATE_TAG']
  options[:Condition] = 'New'
  options[:response_group] = 'Medium'
  options[:sort] = 'salesrank'

  # options[:associate_tag] = {
  #   us: 'schenecalcul-20',
  #   uk: 'schengcalcul-21',
  #   ca: 'schengcalcul-20'
  # }
end
