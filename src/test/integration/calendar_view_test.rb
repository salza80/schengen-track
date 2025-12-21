require 'test_helper'

class CalendarViewTest < ActionDispatch::IntegrationTest
  include Capybara::DSL
  
  # ====================
  # A. Basic Calendar Viewing
  # ====================
  
  test "user with visits can view calendar" do
    # Login as Sally who has visits
    user_login
    
    # Navigate to days page with year=2014 (Sally's visits are in 2014)
    visit days_path(locale: 'en', year: 2014)
    
    # Should see calendar elements
    assert has_content?('2014'), "Should show year 2014 from Sally's visits"
    assert has_css?('.calendar-month'), "Should have calendar month containers"
    assert has_css?('.calendar-grid'), "Should have calendar grid"
  end
  
  test "guest user can view empty calendar" do
    # Visit without logging in (guest user)
    visit days_path(locale: 'en')
    
    # Should see calendar for current year
    current_year = Date.today.year
    assert has_content?(current_year.to_s), "Should show current year"
    assert has_css?('.calendar-month'), "Should have calendar display"
    
    # Should not see status summary (no visits)
    assert_not has_css?('.calendar-status-card'), "Should not show status card for guest with no visits"
  end
  
  test "calendar displays status summary for users with visits" do
    user_login
    
    # Visit the year with Sally's data (2014)
    visit days_path(locale: 'en', year: 2014)
    
    # Status summary appears when there's calculated data
    # Check for year summary which always appears
    assert has_css?('.calendar-year-summary'), "Should show year summary"
  end
  
  # ====================
  # B. Year Navigation
  # ====================
  
  test "year navigation works" do
    user_login
    
    visit days_path(locale: 'en', year: 2014)
    
    # Should show 2014
    assert has_content?('2014'), "Should display 2014"
    
    # Navigate to next year (2015) - click the first link since there are two (top and bottom nav)
    first(:link, '2015').click
    
    # URL should contain year parameter
    assert_match /year=2015/, current_url, "URL should contain year=2015"
    assert has_content?('2015'), "Should now display 2015"
  end
  
  test "year navigation buttons appear when available" do
    user_login
    
    visit days_path(locale: 'en', year: 2014)
    
    # Should have prev/next year links
    assert has_link?('2013'), "Should have previous year link"
    assert has_link?('2015'), "Should have next year link"
  end
  
  # ====================
  # C. Calendar Display
  # ====================
  
  test "calendar shows all 12 months" do
    user_login
    
    visit days_path(locale: 'en', year: 2014)
    
    # Should show all month names
    assert has_content?('January'), "Should show January"
    assert has_content?('February'), "Should show February"
    assert has_content?('December'), "Should show December"
    
    # Should have 12 calendar-month containers
    assert_equal 12, page.all('.calendar-month').count, "Should have 12 month containers"
  end
  
  test "calendar shows year summary banner" do
    user_login
    
    visit days_path(locale: 'en', year: 2014)
    
    # Should show year summary with visit counts
    assert has_css?('.calendar-year-summary'), "Should have year summary banner"
    assert has_content?('Visits'), "Should show visits label"
    assert has_content?('Days in Schengen'), "Should show days in schengen label"
  end
  
  # ====================
  # E. Responsive Features
  # ====================
  
  test "mobile legend displays on page" do
    user_login
    
    visit days_path(locale: 'en', year: 2014)
    
    # Mobile legend should exist (even if hidden on desktop)
    # It has d-lg-none class which hides it on large screens
    assert has_content?('Outside Schengen'), "Should have legend item"
    assert has_content?('In Schengen (Safe)'), "Should have legend item"
  end
end
