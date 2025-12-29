require 'test_helper'

class PeopleControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  
  setup do
    @user = users(:Sally)
    sign_in @user
    @person = people(:sally_person)
  end

  test 'should get index' do
    get people_url(locale: 'en')
    assert_response :success
    assert_select 'h1', text: /Manage People/
  end

  test 'should show all user people' do
    get people_url(locale: 'en')
    assert_response :success
    assert_select 'table tbody tr', count: @user.people.count
  end

  test 'should get new' do
    get new_person_url(locale: 'en')
    assert_response :success
    assert_select 'form'
  end

  test 'should create person' do
    assert_difference('Person.count') do
      post people_url(locale: 'en'), params: {
        person: {
          first_name: 'New',
          last_name: 'Person',
          nationality_id: countries(:Australia).id
        }
      }
    end

    assert_redirected_to people_url(locale: 'en')
    assert_equal 'Person was successfully created.', flash[:notice]
  end

  test 'should not create person without first_name' do
    assert_no_difference('Person.count') do
      post people_url(locale: 'en'), params: {
        person: {
          last_name: 'Test',
          nationality_id: countries(:Australia).id
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get edit_person_url(@person, locale: 'en')
    assert_response :success
    assert_select 'form'
  end

  test 'should update person' do
    patch person_url(@person, locale: 'en'), params: {
      person: {
        first_name: 'Updated',
        last_name: 'Name'
      }
    }
    assert_redirected_to people_url(locale: 'en')
    @person.reload
    assert_equal 'Updated', @person.first_name
    assert_equal 'Name', @person.last_name
  end

  test 'should not update person with invalid data' do
    patch person_url(@person, locale: 'en'), params: {
      person: {
        first_name: ''
      }
    }
    assert_response :unprocessable_entity
    @person.reload
    assert_not_equal '', @person.first_name
  end

  test 'should destroy person if not the last one' do
    # Create another person
    other_person = Person.create!(
      user: @user,
      first_name: 'Another',
      nationality: countries(:Australia),
      is_primary: false
    )

    assert_difference('Person.count', -1) do
      delete person_url(other_person, locale: 'en')
    end

    assert_redirected_to people_url(locale: 'en')
  end

  test 'should not destroy last person' do
    # Delete all but one person
    @user.people.where.not(id: @person.id).destroy_all

    assert_no_difference('Person.count') do
      delete person_url(@person, locale: 'en')
    end

    assert_redirected_to people_url(locale: 'en')
    assert_match /Cannot delete your only person/, flash[:alert]
  end

  test 'should set current person' do
    alt_person = people(:sally_person_alt)
    
    post set_current_person_url(alt_person, locale: 'en')
    assert_redirected_to root_url(locale: 'en')
    assert_equal alt_person.id, session[:current_person_id]
  end

  test 'should not set current person for other user' do
    other_person = people(:test1_person)
    
    assert_raises(ActiveRecord::RecordNotFound) do
      post set_current_person_url(other_person, locale: 'en')
    end
  end

  test 'should make person primary' do
    alt_person = people(:sally_person_alt)
    
    post make_primary_person_url(alt_person, locale: 'en')
    assert_redirected_to people_url(locale: 'en')
    
    @person.reload
    alt_person.reload
    
    assert_not @person.is_primary
    assert alt_person.is_primary
  end

  test 'should not make other user person primary' do
    other_person = people(:test1_person)
    
    assert_raises(ActiveRecord::RecordNotFound) do
      post make_primary_person_url(other_person, locale: 'en')
    end
  end

  test 'guest users can access people pages' do
    # Logout current user
    delete destroy_user_session_url
    
    # Access as guest
    get people_url(locale: 'en')
    assert_response :success
  end
end
