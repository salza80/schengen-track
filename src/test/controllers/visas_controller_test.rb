require 'test_helper'

class VisasControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  setup do
    loginVR
    @visa = visas(:one)
  end

  # test "should get index" do
  #   get :index
  #   assert_response :success
  #   assert_not_nil assigns(:visas)
  # end

  test "should create visa" do
    capture_analytics_events do |events|
      assert_difference('Visa.count') do
        @newVisa = post :create, params: { visa: { start_date: (@visa.start_date + 10.year), end_date: (@visa.end_date + 10.year), no_entries: 1  }}
      end

      assert_equal 1, events.length
      event_name, options = events.fetch(0)
      assert_equal 'user_add_visa', event_name
      assert_equal 'add_visa', options.dig(:params, :action)
    end

    assert_redirected_to visits_path
  end

  test "should not track an invalid visa" do
    capture_analytics_events do |events|
      assert_no_difference('Visa.count') do
        post :create, params: { visa: { start_date: '', end_date: '', no_entries: '' } }, format: :json
      end

      assert_response :unprocessable_entity
      assert_empty events
    end
  end

  test "should update visa" do
    patch :update, params: { id: @visa, visa: { start_date: (@visa.start_date - 1.day), end_date: (@visa.end_date), no_entries: 1  } }
    assert_redirected_to visits_path
  end

  test "should destroy visa" do
    assert_difference('Visa.count', -1) do
      delete :destroy, params: { id: @visa }
    end

    assert_redirected_to visits_path
  end
end
