require 'test_helper'
require 'socket'
require 'timeout'

class ReferrerPolicyBrowserTest < JavascriptIntegrationTest
  test 'cross-origin requests receive no path or query while local navigation retains its return URL' do
    server = TCPServer.new('127.0.0.1', 0)
    receiver_url = "http://127.0.0.1:#{server.addr[1]}/receiver"
    policy = Rails.application.config.content_security_policy
    original_connect_sources = policy.directives['connect-src']&.dup
    # Isolate referrer behavior from CSP, which correctly blocks HTTP in production.
    # This exception exists only for this test's ephemeral loopback receiver.
    policy.connect_src(*policy.directives.fetch('default-src'), receiver_url)
    visit about_path(locale: :en, private_marker: 'referrer-regression')
    source_url = page.current_url
    headers = Queue.new
    receiver = Thread.new do
      socket = server.accept
      begin
        socket.gets
        received = {}
        while (line = socket.gets) && line != "\r\n"
          name, value = line.split(':', 2)
          received[name.downcase] = value.to_s.strip
        end
        headers << received
        socket.write("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      ensure
        socket.close
      end
    end

    page.execute_script('fetch(arguments[0], {mode: "no-cors"})', receiver_url)
    referrer = Timeout.timeout(5) { headers.pop }.fetch('referer')
    source = URI.parse(source_url)
    assert_equal "#{source.scheme}://#{source.host}:#{source.port}/", referrer
    assert_not_includes referrer, 'private_marker'
    assert_not_includes referrer, '/en/about'

    page.execute_script('window.location.assign(arguments[0])', visits_path(locale: :en))
    assert_current_path visits_path(locale: :en)
    assert_equal source_url, page.evaluate_script('document.referrer')
  ensure
    policy.connect_src(*(original_connect_sources || [false])) if policy
    receiver&.join(1)
    receiver&.kill if receiver&.alive?
    receiver&.join
    server&.close
  end
end
