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
    primary_person = @user.people.find_by(is_primary: true)
    patch :update, params: { person: { first_name: 'Updated', last_name: 'Name', nationality_id: primary_person.nationality_id }}
    assert_redirected_to visits_path
    primary_person.reload
    assert_equal 'Updated', primary_person.first_name
    assert_equal 'Name', primary_person.last_name
  end

  test "should destroy user account" do
    login
    people_count = @user.people.count
    assert_difference('User.count', -1) do
      assert_difference('Person.count', -people_count) do
        delete :destroy
      end
    end
    assert_redirected_to root_path
  end

  # test "should destroy person" do
  #   assert_difference('Person.count', -1) do
  #     delete :destroy, id: @person
  #   end

  #   assert_redirected_to people_path
  # end
end
