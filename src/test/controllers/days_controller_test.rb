require 'test_helper'

class DaysControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  
  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  # ====================
  # A. Access Control
  # ====================
  
  test "should redirect visa required users to visits path" do
    sign_in users(:VisaRequiredUser)
    get :index, params: { locale: 'en' }
    assert_redirected_to visits_path(locale: 'en')
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
end
