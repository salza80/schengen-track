require 'test_helper'

class VisitsManagementTest < JavascriptIntegrationTest
  test 'user can view visits page with add button' do
    user_login
    
    visit visits_path(locale: :en)
    assert_text 'Trips', wait: 5
    
    # Verify Add Travel button is present
    assert has_selector?('button[data-action="add-visit"]', wait: 5)
  end
end
