require 'test_helper'

class UsersControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  setup do
    @user = users(:Sally)
  end

  # test "should get index" do
  #   get :index
  #   assert_response :success
  #   assert_not_nil assigns(:people)
  # end

  # test "should get new" do
  #   get :new
  #   assert_response :success
  # end

  # test "should create person" do
  #   assert_difference('Person.count') do
  #     post :create, person: {  }
  #   end

  #   assert_redirected_to person_path(assigns(:person))
  # end

  # test "should show person" do
  #   get :show, id: @person
  #   assert_response :success
  # end

  test "should get edit" do
    login
    get :edit
    assert_response :success
  end

  test "should update person" do
    login
    patch :update, user: { first_name: @user.first_name, last_name: @user.last_name, nationality_id: @user.nationality_id }
    assert_redirected_to visits_path
  end

  # test "should destroy person" do
  #   assert_difference('Person.count', -1) do
  #     delete :destroy, id: @person
  #   end

  #   assert_redirected_to people_path
  # end
end
