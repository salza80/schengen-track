require 'test_helper'
require 'mail'
require 'open3'
require 'net/smtp'
require 'socket'
require 'timeout'

class ProductionMailSecurityTest < ActiveSupport::TestCase
  test 'production recovery mail and route helpers generate HTTPS links on the configured domain' do
    [nil, 'test.schengen-calculator.com'].each do |domain|
      settings = production_configuration(domain)
      link = Nokogiri::HTML5.fragment(settings.fetch('mail_html')).at_css('a')['href']
      uri = URI.parse(link)

      assert_equal 'https', uri.scheme
      assert_equal domain || 'schengen-calculator.com', uri.host
      assert_equal '/users/password/edit', uri.path
      assert_equal 'recovery-test-token', Rack::Utils.parse_query(uri.query)['reset_password_token']
      assert_equal link, settings.fetch('route_url')
    end
  end

  test 'production enforces HTTPS without redirecting forwarded HTTPS requests in a loop' do
    settings = production_configuration

    assert_equal 301, settings.fetch('http_status')
    assert_equal 'https://schengen-calculator.com/api/docs', settings.fetch('http_location')
    assert_equal 200, settings.fetch('https_status')
    assert_includes settings.fetch('https_hsts'), 'max-age='
  end

  test 'production SMTP refuses a server without STARTTLS before sending credentials or mail' do
    with_smtp_server do |server, commands|
      worker = Thread.new do
        socket = server.accept
        socket.puts "220 smtp.example ESMTP\r"
        commands << socket.gets
        socket.write "250-smtp.example\r\n250 AUTH PLAIN\r\n"
        commands << socket.gets
      ensure
        socket&.close
      end

      assert_raises(Net::SMTPUnsupportedCommand) { deliver_to(server) }
      assert worker.join(5), 'SMTP client did not close the rejected connection'
      refute commands.compact.any? { |command| command.match?(/\A(?:AUTH|MAIL|RCPT|DATA)\b/i) }
    ensure
      worker&.kill&.join
    end
  end

  test 'production SMTP refuses an untrusted TLS certificate before sending credentials or mail' do
    with_smtp_server do |server, commands|
      worker = Thread.new do
        socket = server.accept
        socket.puts "220 smtp.example ESMTP\r"
        commands << socket.gets
        socket.write "250-smtp.example\r\n250-STARTTLS\r\n250 AUTH PLAIN\r\n"
        commands << socket.gets
        socket.write "220 Begin TLS\r\n"
        tls = OpenSSL::SSL::SSLSocket.new(socket, untrusted_tls_context)
        tls.sync_close = true
        tls.accept
        commands << tls.gets
      rescue OpenSSL::SSL::SSLError, Errno::ECONNRESET
        # The client must reject this self-signed certificate.
      ensure
        tls&.close
        socket&.close
      end

      error = assert_raises(OpenSSL::SSL::SSLError) { deliver_to(server) }
      assert_match(/certificate verify failed/i, error.message)
      assert worker.join(5), 'SMTP client did not close the rejected TLS connection'
      assert_equal "STARTTLS\r\n", commands.fetch(1)
      refute commands.compact.any? { |command| command.match?(/\A(?:AUTH|MAIL|RCPT|DATA)\b/i) }
    ensure
      worker&.kill&.join
    end
  end

  private

  def production_configuration(domain = nil)
    # Boot the real production application with only dummy credentials. Keep
    # production's configuration and URL generation separate from test mode.
    self.class.instance_variable_get(:@production_configurations) ||
      self.class.instance_variable_set(:@production_configurations, {})
    configurations = self.class.instance_variable_get(:@production_configurations)
    configurations[domain] ||= begin
      env = ENV.slice('PATH', 'HOME', 'GEM_HOME', 'GEM_PATH', 'BUNDLE_GEMFILE')
      env.merge!(
        'RAILS_ENV' => 'production',
        'SECRET_KEY_BASE' => 'production-mail-security-test-' * 4,
        'FACEBOOK_ID' => 'test-facebook-id',
        'FACEBOOK_SECRET' => 'test-facebook-secret',
        'MAIL_SECURITY_TEST_DATABASE' => ActiveRecord::Base.connection_db_config.configuration_hash.to_json,
        'DOMAIN' => domain
      )
      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, '-e', <<~'RUBY', chdir: Rails.root, unsetenv_others: true)
        require './config/environment'
        ActiveRecord::Base.establish_connection(JSON.parse(ENV.fetch('MAIL_SECURITY_TEST_DATABASE')))
        mail = Devise.mailer.reset_password_instructions(
          User.new(email: 'recovery@example.com'), 'recovery-test-token'
        )
        host = Rails.application.routes.default_url_options.fetch(:host)
        # The JSON endpoint works before CI compiles production assets.
        http = Rack::MockRequest.env_for("http://#{host}/api/docs")
        http_status, http_headers, http_body = Rails.application.call(http)
        http_body.close if http_body.respond_to?(:close)
        # Match the forwarded HTTPS scheme supplied by the Lambda adapter.
        https = Rack::MockRequest.env_for("https://#{host}/api/docs", 'HTTP_X_FORWARDED_PROTO' => 'https')
        https_status, https_headers, https_body = Rails.application.call(https)
        https_body.close if https_body.respond_to?(:close)
        puts JSON.generate(
          mail_html: mail.body.decoded,
          route_url: Rails.application.routes.url_helpers.edit_user_password_url(reset_password_token: 'recovery-test-token'),
          smtp: ActionMailer::Base.smtp_settings.slice(:address, :port, :domain, :authentication, :enable_starttls, :enable_starttls_auto, :openssl_verify_mode),
          http_status: http_status, http_location: http_headers['location'],
          https_status: https_status, https_hsts: https_headers['strict-transport-security']
        )
      RUBY
      assert status.success?, "Production configuration probe failed: #{stderr.lines.first(12).join}"
      JSON.parse(stdout.lines.last)
    end
  end

  def deliver_to(server)
    settings = production_configuration.fetch('smtp').symbolize_keys
    settings[:enable_starttls] = settings[:enable_starttls].to_sym if settings[:enable_starttls].is_a?(String)
    settings.merge!(address: '127.0.0.1', port: server.addr[1], user_name: 'smtp-test-user', password: 'smtp-test-password', open_timeout: 3, read_timeout: 3)
    mail = Mail.new(from: 'sender@example.com', to: 'recipient@example.com', subject: 'TLS regression', body: 'Test message')
    Timeout.timeout(5) { Mail::SMTP.new(settings).deliver!(mail) }
  end

  def with_smtp_server
    server = TCPServer.new('127.0.0.1', 0)
    yield server, []
  ensure
    server&.close
  end

  def untrusted_tls_context
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = cert
      context.key = key
    end
  end
end
