require 'test_helper'

class AccountDeletionAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous_forgery_protection
  end

  test 'a calculation-link guest cannot delete its user or any travel data with a valid CSRF token' do
    guest = establish_calculation_guest
    person = guest.people.find_by!(is_primary: true)

    [:html, :json].each do |format|
      csrf = fresh_csrf
      assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
        delete delete_account_path(locale: :en, format: format), params: { authenticity_token: csrf }
      end
      assert_response :forbidden
      assert User.exists?(guest.id)
      assert_equal 1, person.visits.count
      assert_equal 1, person.visas.count
      assert_equal guest.id, session[:guest_user_id]
    end

    get visits_path(locale: :en)
    assert_response :success
    assert_equal guest.id, session[:guest_user_id]
  end

  test 'anonymous deletion requests are rejected even with a valid CSRF token' do
    csrf = fresh_csrf
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      delete delete_account_path(locale: :en), params: { authenticity_token: csrf }
    end
    assert_response :forbidden
  end

  test 'an authenticated guest is still ineligible for account deletion' do
    guest = establish_calculation_guest
    sign_in guest
    csrf = fresh_csrf
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      delete delete_account_path(locale: :en), params: { authenticity_token: csrf }
    end
    assert_response :forbidden
    assert User.exists?(guest.id)
  end

  test 'a registered account can delete itself while separate guest records are preserved' do
    guest = establish_calculation_guest
    account = users(:Sally)
    person_ids = account.people.ids
    post user_session_path(locale: :en), params: {
      authenticity_token: fresh_csrf,
      user: { email: account.email, password: 'password' }
    }
    assert_response :redirect
    csrf = fresh_csrf

    assert_difference('User.count', -1) do
      delete delete_account_path(locale: :en), params: { authenticity_token: csrf }
    end
    assert_redirected_to root_path(locale: :en)
    refute User.exists?(account.id)
    assert_empty Person.where(user_id: account.id)
    assert_empty Visit.where(person_id: person_ids)
    assert_empty Visa.where(person_id: person_ids)
    assert_nil request.env['warden'].user(:user)
    assert User.exists?(guest.id)
    assert_equal 1, guest.people.first.visits.count
    assert_equal 1, guest.people.first.visas.count
  end

  test 'registered account deletion still requires CSRF protection' do
    account = users(:Sally)
    sign_in account
    fresh_csrf
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      assert_raises(ActionController::InvalidAuthenticityToken) do
        delete delete_account_path(locale: :en)
      end
    end
    assert User.exists?(account.id)
  end

  private

  def establish_calculation_guest
    source = User.create!(guest: true, email: "delete_guest_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                          first_name: 'Guest', last_name: 'Traveler', nationality: countries(:USA))
    person = source.people.find_by!(is_primary: true)
    person.visits.create!(country: countries(:Germany), entry_date: '2027-01-01', exit_date: '2027-01-05')
    person.visas.create!(visa_type: 'S', start_date: '2027-01-01', end_date: '2027-06-01', no_entries: 0)
    import_guest_calculation(source)
  end

  def fresh_csrf
    get csrf_token_path(locale: :en), as: :json
    JSON.parse(response.body).fetch('token')
  end
end
