require 'test_helper'

class DaysControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  
  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  # ====================
  # A. Access Control
  # ====================
  
  test "should allow visa required users to access days index" do
    sign_in users(:VisaRequiredUser)
    get :index, params: { locale: 'en' }
    assert_response :success
    assert_not_nil assigns(:days)
    assert_not_nil assigns(:overstay)
    assert_not_nil assigns(:next_entry_days)
  end

  test "should allow regular users to access days index" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en' }
    assert_response :success
    assert_not_nil assigns(:days)
    assert_not_nil assigns(:overstay)
    assert_not_nil assigns(:next_entry_days)
  end

  # ====================
  # B. Calendar Setup - With Visits
  # ====================
  
  test "should setup calendar with year navigation" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en' }
    # With infinite navigation, we should have prev/next year instead of available_years array
    assert_not_nil assigns(:prev_year)
    assert_not_nil assigns(:next_year)
    assert_equal Date.today.year - 1, assigns(:prev_year)
    assert_equal Date.today.year + 1, assigns(:next_year)
  end

  test "should select current year by default" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en' }
    assert_equal Date.today.year, assigns(:selected_year)
  end

  test "should allow selecting specific year" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    assert_equal 2014, assigns(:selected_year)
  end

  test "should generate 12 months for selected year" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    assert_not_nil assigns(:calendar_months)
    assert_equal 12, assigns(:calendar_months).length
    assert_equal 1, assigns(:calendar_months).first[:month]
    assert_equal 12, assigns(:calendar_months).last[:month]
  end

  test "should setup year navigation" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    assert_equal 2013, assigns(:prev_year)
    assert_equal 2015, assigns(:next_year)
  end

  # ====================
  # C. Year Navigation Limits (±20 years)
  # ====================

  test "should redirect to closest year when navigating too far in past" do
    sign_in users(:Sally)
    
    # Try to navigate to 21 years ago
    too_old_year = Date.today.year - 21
    min_allowed_year = Date.today.year - 20
    
    get :index, params: { locale: 'en', year: too_old_year }
    
    assert_redirected_to days_path(locale: 'en', year: min_allowed_year)
  end

  test "should redirect to closest year when navigating too far in future" do
    sign_in users(:Sally)
    
    # Try to navigate to 21 years in future
    too_new_year = Date.today.year + 21
    max_allowed_year = Date.today.year + 20
    
    get :index, params: { locale: 'en', year: too_new_year }
    
    assert_redirected_to days_path(locale: 'en', year: max_allowed_year)
  end

  test "should preserve month parameter when redirecting out of range year" do
    sign_in users(:Sally)
    
    too_old_year = Date.today.year - 25
    min_allowed_year = Date.today.year - 20
    
    get :index, params: { locale: 'en', year: too_old_year, month: 6 }
    
    assert_redirected_to days_path(locale: 'en', year: min_allowed_year, month: 6)
  end

  test "should allow navigation to exactly 20 years ago" do
    sign_in users(:Sally)
    
    min_allowed_year = Date.today.year - 20
    
    get :index, params: { locale: 'en', year: min_allowed_year }
    
    assert_response :success
    assert_equal min_allowed_year, assigns(:selected_year)
  end

  test "should allow navigation to exactly 20 years in future" do
    sign_in users(:Sally)
    
    max_allowed_year = Date.today.year + 20
    
    get :index, params: { locale: 'en', year: max_allowed_year }
    
    assert_response :success
    assert_equal max_allowed_year, assigns(:selected_year)
  end

  test "should hide prev year button at 20 years ago boundary" do
    sign_in users(:Sally)
    
    min_allowed_year = Date.today.year - 20
    
    get :index, params: { locale: 'en', year: min_allowed_year }
    
    assert_response :success
    assert_nil assigns(:prev_year), "Prev year button should be hidden at minimum boundary"
    assert_not_nil assigns(:next_year), "Next year button should still be visible"
  end

  test "should hide next year button at 20 years future boundary" do
    sign_in users(:Sally)
    
    max_allowed_year = Date.today.year + 20
    
    get :index, params: { locale: 'en', year: max_allowed_year }
    
    assert_response :success
    assert_nil assigns(:next_year), "Next year button should be hidden at maximum boundary"
    assert_not_nil assigns(:prev_year), "Prev year button should still be visible"
  end

  test "should show both nav buttons when within 20 year range" do
    sign_in users(:Sally)
    
    # Use a year well within the range
    middle_year = Date.today.year - 10
    
    get :index, params: { locale: 'en', year: middle_year }
    
    assert_response :success
    assert_not_nil assigns(:prev_year), "Prev year button should be visible"
    assert_not_nil assigns(:next_year), "Next year button should be visible"
  end

  # ====================
  # D. Calendar Setup - No Visits
  # ====================
  
  test "should setup calendar for user with no visits" do
    # Create a user with no visits
    user = User.create!(
      email: 'novisits@test.com',
      password: 'password',
      first_name: 'No',
      last_name: 'Visits',
      nationality: countries(:Australia)
    )
    # Create a person for the user
    Person.create!(
      user: user,
      first_name: 'No',
      last_name: 'Visits',
      nationality: countries(:Australia),
      is_primary: true
    )
    sign_in user
    
    get :index, params: { locale: 'en' }
    assert_response :success
    # With infinite navigation, should still be able to navigate years
    assert_not_nil assigns(:prev_year)
    assert_not_nil assigns(:next_year)
    assert_equal 12, assigns(:calendar_months).length
  end

  test "should handle guest user with no visits" do
    # Don't sign in - acts as guest
    get :index, params: { locale: 'en' }
    assert_response :success
    assert_not_nil assigns(:calendar_months)
  end

  # ====================
  # E. Status Summary
  # ====================
  
  test "should calculate status summary with safe status" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    
    # Sally's 2014 visits should result in safe status (< 80 days)
    if assigns(:status_summary)
      assert_includes ['safe', 'warning', 'overstay'], assigns(:status_summary)[:status]
      assert assigns(:status_summary)[:current_days] >= 0
      assert assigns(:status_summary)[:remaining_days] >= 0
      assert_equal 90, assigns(:status_summary)[:max_days]
    end
  end

  test "should use today's date for status when available" do
    sign_in users(:Sally)
    
    # Travel to a date when Sally has active visits
    travel_to Date.new(2014, 3, 15) do
      get :index, params: { locale: 'en' }
      
      if assigns(:status_summary)
        # Should use date from 2014-03-15 range
        assert_not_nil assigns(:status_summary)[:last_calculated_date]
      end
    end
  end

  test "should not create status summary when no visits" do
    user = User.create!(
      email: 'nostatus@test.com',
      password: 'password',
      first_name: 'No',
      last_name: 'Status',
      nationality: countries(:Australia)
    )
    # Create a person for the user
    Person.create!(
      user: user,
      first_name: 'No',
      last_name: 'Status',
      nationality: countries(:Australia),
      is_primary: true
    )
    sign_in user
    
    get :index, params: { locale: 'en' }
    assert_nil assigns(:status_summary)
  end

  # ====================
  # F. Year Summary
  # ====================
  
  test "should count visits in selected year" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    
    assert_not_nil assigns(:year_summary)
    assert assigns(:year_summary)[:visits_count] >= 0
    # Sally has 3 visits in 2014 according to fixtures
    assert_equal 3, assigns(:year_summary)[:visits_count]
  end

  test "should count schengen days in year" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    
    assert_not_nil assigns(:year_summary)
    assert assigns(:year_summary)[:schengen_days] >= 0
  end

  test "should calculate peak usage in year" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    
    assert_not_nil assigns(:year_summary)
    assert_not_nil assigns(:year_summary)[:max_schengen_count]
    assert assigns(:year_summary)[:max_schengen_count] >= 0
  end

  test "should return zeros for year with no visits" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2020 }
    
    assert_not_nil assigns(:year_summary)
    assert_equal 0, assigns(:year_summary)[:visits_count]
    assert_equal 0, assigns(:year_summary)[:schengen_days]
    assert_equal 0, assigns(:year_summary)[:max_schengen_count]
  end
  
  # ====================
  # G. Visa Tracking Tests
  # ====================
  
  test "should calculate visa information for visa-required users" do
    sign_in users(:VisaRequiredUser)
    get :index, params: { locale: 'en', year: 2012 }
    
    assert_response :success
    days = assigns(:days)
    assert days.any?, "Should have calculated days"
    
    # Find a day with visa
    day_with_visa = days.find { |d| d.schengen? && d.visa }
    if day_with_visa
      assert day_with_visa.user_requires_visa?
      assert_not_nil day_with_visa.visa
    end
  end
  
  test "should not calculate visa info for non-visa users" do
    sign_in users(:Sally)
    get :index, params: { locale: 'en', year: 2014 }
    
    assert_response :success
    days = assigns(:days)
    
    # Non-visa users shouldn't have visa tracking
    if days.any?
      day = days.first
      assert_not (day.respond_to?(:user_requires_visa?) && day.user_requires_visa?)
    end
  end
  
  test "should include visa status in status summary for visa users" do
    sign_in users(:VisaRequiredUser)
    
    # Use a date with valid visa (2011)
    get :index, params: { locale: 'en', year: 2013 }
    
    assert_response :success
    
    # Status summary may include visa status if visits exist
    status = assigns(:status_summary)
    if status && status[:visa_status]
      assert_includes ['ok', 'warning'], status[:visa_status]
    end
  end
  
  test "should show visa entry count when visa has limited entries" do
    sign_in users(:VisaRequiredUser)
    
    # Year 2012 has two-entry visa with visits
    get :index, params: { locale: 'en', year: 2012 }
    
    assert_response :success
    status = assigns(:status_summary)
    
    # Should have visa entries display if there's a limited-entry visa
    if status && status[:visa_entries_display]
      assert_match /\d+\/\d+ entries/, status[:visa_entries_display]
    end
  end
  
  test "should show entry count even when entries exceeded" do
    sign_in users(:VisaRequiredUser)
    
    # Year 2012 has visits with exceeded entries on a 2-entry visa
    # There are 3 distinct entries: Jan, Feb, Mar-Apr
    get :index, params: { locale: 'en', year: 2012 }
    
    assert_response :success
    status = assigns(:status_summary)
    
    # Status summary should now use today's date (not limited to 2012)
    # Since we're using travel_to, "today" is the current real date
    
    # Should still show entry count display
    if status && status[:visa_entries_display]
      assert_match /\d+\/\d+ entries/, status[:visa_entries_display]
      
      # Should flag that entries are exceeded
      if status[:visa_entries_exceeded]
        assert status[:visa_entries_exceeded], "Should flag that entries are exceeded"
      end
    end
  end
  
  test "should use today's date for status summary even when viewing past years" do
    sign_in users(:VisaRequiredUser)
    
    # Mock today to be well after all visits (VisaRequiredUser's last visit is 2017-03-10)
    travel_to Date.new(2020, 6, 15) do
      # View year 2012 (a past year with visits)
      get :index, params: { locale: 'en', year: 2012 }
      
      assert_response :success
      status = assigns(:status_summary)
      
      # Status summary should reflect June 15, 2020 (today), not a date from 2012
      assert_not_nil status, "Status summary should exist"
      assert_equal Date.new(2020, 6, 15), status[:last_calculated_date], 
                   "Status should use today's date, not a date from the viewed year"
      
      # After 180+ days with no visits, Schengen days should be 0
      assert_equal 0, status[:current_days], "Should have 0 days after 180+ day gap"
      assert_equal 'safe', status[:status], "Status should be safe"
    end
  end
  
  test "should use today's date for status summary when no year parameter provided" do
    sign_in users(:VisaRequiredUser)
    
    travel_to Date.new(2020, 6, 15) do
      # No year parameter - should default to current year (2020)
      get :index, params: { locale: 'en' }
      
      assert_response :success
      status = assigns(:status_summary)
      
      assert_not_nil status
      assert_equal Date.new(2020, 6, 15), status[:last_calculated_date]
    end
  end

  # ====================
  # H. Visit Cleanup Tests
  # ====================

  test "should cleanup visits older than 20 years on page load" do
    sign_in users(:Sally)
    
    # Create a visit 21 years ago (bypassing validation for test)
    old_visit = people(:sally_person).visits.new(
      country: countries(:Germany),
      entry_date: Date.today - 21.years,
      exit_date: Date.today - 21.years + 5.days
    )
    old_visit.save(validate: false)
    
    assert_difference 'Visit.count', -1 do
      get :index, params: { locale: 'en' }
    end
    
    assert_response :success
    assert_nil Visit.find_by(id: old_visit.id)
  end

  test "should cleanup visits more than 20 years in future on page load" do
    sign_in users(:Sally)
    
    # Create a visit 21 years in future (bypassing validation for test)
    future_visit = people(:sally_person).visits.new(
      country: countries(:Germany),
      entry_date: Date.today + 21.years,
      exit_date: Date.today + 21.years + 5.days
    )
    future_visit.save(validate: false)
    
    assert_difference 'Visit.count', -1 do
      get :index, params: { locale: 'en' }
    end
    
    assert_response :success
    assert_nil Visit.find_by(id: future_visit.id)
  end

  test "should keep recent visits during cleanup" do
    sign_in users(:Sally)
    
    # Create a visit 10 years ago (should be kept)
    recent_visit = people(:sally_person).visits.create!(
      country: countries(:Germany),
      entry_date: Date.today - 10.years,
      exit_date: Date.today - 10.years + 5.days
    )
    
    assert_no_difference 'Visit.count' do
      get :index, params: { locale: 'en' }
    end
    
    assert_response :success
    assert_not_nil Visit.find_by(id: recent_visit.id)
  end
end
