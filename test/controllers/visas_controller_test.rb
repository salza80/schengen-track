require 'test_helper'

class VisasControllerTest < ActionController::TestCase
  setup do
    @visa = visas(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:visas)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create visa" do
    assert_difference('Visa.count') do
      post :create, visa: {  }
    end

    assert_redirected_to visa_path(assigns(:visa))
  end

  test "should show visa" do
    get :show, id: @visa
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @visa
    assert_response :success
  end

  test "should update visa" do
    patch :update, id: @visa, visa: {  }
    assert_redirected_to visa_path(assigns(:visa))
  end

  test "should destroy visa" do
    assert_difference('Visa.count', -1) do
      delete :destroy, id: @visa
    end

    assert_redirected_to visas_path
  end
end
