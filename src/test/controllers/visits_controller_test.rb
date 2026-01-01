require 'test_helper'

class VisitsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  
  setup do
    login
    @visit = visits(:one)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:visits)
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create visit' do
    assert_difference('Visit.count') do
      @newVisit = post :create, params: { visit: { entry_date: (@visit.entry_date - 1.year), country_id: @visit.country_id, exit_date: (@visit.exit_date - 1.year) }}
    end
    assert_redirected_to visits_path
  end

  test 'should show visit' do
    get :show, params: { id: @visit }
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @visit }
    assert_response :success
  end

  test 'should update visit' do
    patch :update, params: { id: @visit, visit: { entry_date: @visit.entry_date, country_id: @visit.country_id, exit_date: @visit.exit_date }}
    assert_redirected_to visits_path
  end

  test 'should destroy visit' do
    assert_difference('Visit.count', -1) do
      delete :destroy, params: { id: @visit }
    end

    assert_redirected_to visits_path
  end

  # Test safe_redirect_path? security validation
  test 'safe_redirect_path? allows valid calendar paths with query params' do
    controller = VisitsController.new
    assert controller.send(:safe_redirect_path?, '/days?year=2025&month=1&day=15')
    assert controller.send(:safe_redirect_path?, '/en/days/2025/12')
    assert controller.send(:safe_redirect_path?, '/ar/days')
  end

  test 'safe_redirect_path? allows valid visits paths' do
    controller = VisitsController.new
    assert controller.send(:safe_redirect_path?, '/visits')
    assert controller.send(:safe_redirect_path?, '/de/visits/123/edit')
    assert controller.send(:safe_redirect_path?, '/visits?page=2')
  end

  test 'safe_redirect_path? rejects external URLs with http scheme' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, 'http://evil.com/days')
    refute controller.send(:safe_redirect_path?, 'https://evil.com/days')
  end

  test 'safe_redirect_path? rejects protocol-relative URLs' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, '//evil.com/days')
    refute controller.send(:safe_redirect_path?, '//evil.com')
  end

  test 'safe_redirect_path? rejects javascript scheme' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, 'javascript:alert(1)')
    refute controller.send(:safe_redirect_path?, 'javascript:alert(document.cookie)')
  end

  test 'safe_redirect_path? rejects data URLs' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, 'data:text/html,<script>alert(1)</script>')
  end

  test 'safe_redirect_path? rejects blank or nil paths' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, nil)
    refute controller.send(:safe_redirect_path?, '')
    refute controller.send(:safe_redirect_path?, '   ')
  end

  test 'safe_redirect_path? rejects paths not starting with slash' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, 'days/2025/12')
    refute controller.send(:safe_redirect_path?, 'visits')
  end

  test 'safe_redirect_path? rejects non-whitelisted paths' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, '/admin')
    refute controller.send(:safe_redirect_path?, '/api/secret')
    refute controller.send(:safe_redirect_path?, '/en/admin')
    refute controller.send(:safe_redirect_path?, '/blog/posts')
  end

  test 'safe_redirect_path? handles invalid URI gracefully' do
    controller = VisitsController.new
    refute controller.send(:safe_redirect_path?, 'ht!tp://invalid')
  end

  # Test destroy redirect with referer header
  test 'destroy redirects to calendar when referer is calendar page' do
    @request.headers['HTTP_REFERER'] = 'http://test.host/en/days?year=2025&month=1'
    delete :destroy, params: { id: @visit }
    assert_redirected_to '/en/days?year=2025&month=1'
  end

  test 'destroy ignores malicious referer' do
    @request.headers['HTTP_REFERER'] = 'http://evil.com/days'
    delete :destroy, params: { id: @visit }
    # Should fall back to default redirect
    assert_redirected_to visits_path
  end

  test 'destroy ignores referer to non-whitelisted path' do
    @request.headers['HTTP_REFERER'] = 'http://test.host/admin'
    delete :destroy, params: { id: @visit }
    # Should fall back to default redirect
    assert_redirected_to visits_path
  end

  test 'destroy respects referer header for calendar redirect' do
    @request.env['HTTP_REFERER'] = days_path(locale: :en, year: 2025, month: 12)
    delete :destroy, params: { id: @visit }
    # Should redirect to calendar with year/month from deleted visit
    assert_response :redirect
    assert_match /\/days/, @response.location
  end
end
