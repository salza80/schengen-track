require 'test_helper'

class UnusedFrameworkRoutesTest < ActionDispatch::IntegrationTest
  test 'unused upload and mailbox endpoints are not mounted' do
    [
      [:post, '/rails/active_storage/direct_uploads'],
      [:get, '/rails/active_storage/blobs/redirect/example/file.txt'],
      [:post, '/rails/action_mailbox/ingresses/relay/inbound_emails'],
      [:get, '/rails/conductor/action_mailbox/inbound_emails']
    ].each do |method, path|
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path(path, method: method)
      end
    end
  end
end
