require 'test_helper'

class PeopleControllerTest < ActionController::TestCase
  include Devise::TestHelpers
  setup do
    @person = people(:Sally)
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
    patch :update, person: { first_name: @person.first_name, last_name: @person.last_name, nationality_id: @person.nationality_id }
    assert_redirected_to visits_path
  end

  # test "should destroy person" do
  #   assert_difference('Person.count', -1) do
  #     delete :destroy, id: @person
  #   end

  #   assert_redirected_to people_path
  # end
end
