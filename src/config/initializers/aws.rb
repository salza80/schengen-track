Aws.config.update({
  region: 'eu-central-1',
  credentials: Aws::Credentials.new(Rails.application.secrets.aws_access_key_id, Rails.application.secrets.aws_secret_key),
})

