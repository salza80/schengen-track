require 'test_helper'

class VisitsControllerTest < ActionController::TestCase
  setup do
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
      post :create, visit: { entry_date: @visit.entry_date, country_id: @visit.country_id, exit_date: @visit.exit_date }
    end

    assert_redirected_to visit_path(assigns(:visit))
  end

  test 'should show visit' do
    get :show, id: @visit
    assert_response :success
  end

  test 'should get edit' do
    get :edit, id: @visit
    assert_response :success
  end

  test 'should update visit' do
    patch :update, id: @visit, visit: { entry_date: @visit.entry_date, country_id: @visit.country_id, exit_date: @visit.exit_date }
    assert_redirected_to visit_path(assigns(:visit))
  end

  test 'should destroy visit' do
    assert_difference('Visit.count', -1) do
      delete :destroy, id: @visit
    end

    assert_redirected_to visits_path
  end
end
