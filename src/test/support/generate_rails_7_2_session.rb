# Run with the Rails 7.2.4 bundle: bundle exec rails runner test/support/generate_rails_7_2_session.rb
# This fixture deliberately uses a public test key; never use production secrets.
raise 'Generate this historical fixture only with Rails 7.2.4' unless Rails.version == '7.2.4'

require 'action_dispatch/testing/integration'
secret = 'schengen-legacy-session-compatibility-test-only-' * 2
request_env = {
  'action_dispatch.key_generator' => ActiveSupport::CachingKeyGenerator.new(
    ActiveSupport::KeyGenerator.new(secret, iterations: 1000)
  )
}
session = ActionDispatch::Integration::Session.new(Rails.application)
session.https!
session.patch('/en/calculator_preferences', params: { nationality_code: 'IN', destination: 'trips' }, env: request_env)
raise "Preference request failed: #{session.response.status}" unless session.response.status == 302
session.get('/en/csrf_token', env: request_env)
raise "CSRF bootstrap failed: #{session.response.status}" unless session.response.status == 200
cookie = session.response.headers.fetch('Set-Cookie').split(';').first
fixture = {
  rails_version: Rails.version,
  secret_key_base: secret,
  cookie: cookie,
  csrf_token: JSON.parse(session.response.body).fetch('token')
}
File.write(Rails.root.join('test/fixtures/rails_7_2_session.json'), JSON.pretty_generate(fixture) + "\n")
