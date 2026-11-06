require 'test_helper'

class CalculationClaimSecurityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @source = create_source
    @token = @source.signed_id(purpose: :agent_calculation, expires_in: 30.days)
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous_forgery_protection
  end

  test 'opening a bearer link only renders a protected confirmation' do
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      get calculation_link_path(@token), headers: { 'Sec-Fetch-Site' => 'cross-site' }
    end
    assert_response :success
    assert_nil session[:guest_user_id]
    assert_nil session[:current_person_id]
    assert_nil @source.reload.calculation_claimed_at
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    assert_equal 'private, no-store', response.headers['Cache-Control']
    assert_includes response.headers['Content-Security-Policy'], "form-action 'self'"
    assert_select 'script, iframe, img[src^="http"], link[href^="http"]', count: 0
    assert_select "form[action='#{claim_calculation_path}'][method='post']" do
      assert_select 'input[name="token"]', count: 1
      assert_select 'input[name="authenticity_token"]', count: 1
    end
  end

  test 'both legacy query entry points lead to confirmation without adopting identity' do
    [days_path(locale: :en), visits_path(locale: :en)].each do |path|
      assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
        get path, params: { guest_calculation: @token }, headers: { 'Sec-Fetch-Site' => 'cross-site' }
      end
      assert_redirected_to calculation_link_path(@token)
      assert_equal 'no-referrer', response.headers['Referrer-Policy']
      assert_nil session[:guest_user_id]
      assert_nil session[:current_person_id]
    end
  end

  test 'cross-site navigation cannot replace an existing calculator or capture later submissions' do
    existing = import_guest_calculation(create_source(first_name: 'Existing'))
    existing_person = existing.people.find_by!(is_primary: true)
    [calculation_link_path(@token), days_path(locale: :en, guest_calculation: @token)].each do |path|
      get path, headers: { 'Sec-Fetch-Site' => 'cross-site' }
      assert_equal existing.id, session[:guest_user_id]
      assert_equal existing_person.id, session[:current_person_id]
    end

    post visits_path(locale: :en), params: {
      authenticity_token: fresh_csrf,
      visit: { country_id: countries(:Germany).id, entry_date: '2027-02-01', exit_date: '2027-02-05' }
    }
    assert_response :redirect
    assert_equal 2, existing_person.visits.count
    assert_equal 1, @source.people.first.visits.count
    assert_nil @source.reload.calculation_claimed_at
  end

  test 'missing and invalid CSRF tokens cannot consume a link or create records' do
    [nil, 'invalid'].each do |csrf|
      assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
        assert_raises(ActionController::InvalidAuthenticityToken) do
          post claim_calculation_path, params: { token: @token, authenticity_token: csrf }
        end
      end
      assert_nil @source.reload.calculation_claimed_at
      fresh_csrf
      assert_nil session[:guest_user_id]
    end
  end

  test 'legacy tokens cannot select an external redirect destination' do
    ['https://evil.example/path', '//evil.example/path', "\n//evil.example/path"].each do |token|
      get days_path(locale: :en), params: { guest_calculation: token }
      assert_response :redirect
      assert_equal 'www.example.com', URI.parse(response.location).host
      assert URI.parse(response.location).path.start_with?('/calculations/')
      assert_nil session[:guest_user_id]
    end
  end

  test 'another browser cannot use the confirmation CSRF token' do
    get calculation_link_path(@token)
    csrf = form_csrf
    reset!
    assert_no_difference('User.count') do
      assert_raises(ActionController::InvalidAuthenticityToken) do
        post claim_calculation_path, params: { token: @token, authenticity_token: csrf }
      end
    end
    assert_nil @source.reload.calculation_claimed_at
  end

  test 'confirmed import is independent and every token for the source is consumed' do
    second_token = @source.signed_id(purpose: :agent_calculation, expires_in: 1.day)
    get calculation_link_path(@token)
    post claim_calculation_path, params: { token: @token, authenticity_token: form_csrf },
         headers: { 'Origin' => 'null' }
    assert_response :see_other
    imported = User.find(session[:guest_user_id])
    refute_equal @source, imported
    person = imported.people.find(session[:current_person_id])
    assert_equal 1, person.visits.count
    assert_equal 1, person.visas.count
    assert @source.reload.calculation_claimed_at.present?

    person.visits.create!(country: countries(:Germany), entry_date: '2027-02-01', exit_date: '2027-02-05')
    assert_equal 1, @source.people.first.visits.count
    original_session = imported.id
    assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
      post claim_calculation_path, params: { token: second_token, authenticity_token: fresh_csrf }
    end
    assert_equal original_session, session[:guest_user_id]
    reset!
    get calculation_link_path(@token)
    assert_redirected_to root_path(locale: :en)
    assert_nil session[:guest_user_id]
    assert_equal I18n.t('calculation_claim.invalid'), flash[:alert]
  end

  test 'confirmation preserves existing guest travelers in a fresh private identity' do
    existing = import_guest_calculation(create_source(first_name: 'Existing'))
    existing.people.create!(first_name: 'Companion', last_name: 'Traveler', nationality: countries(:USA))
    get calculation_link_path(@token)
    assert_equal existing.id, session[:guest_user_id]
    post claim_calculation_path, params: { token: @token, authenticity_token: form_csrf }
    assert_response :see_other
    imported = User.find(session[:guest_user_id])
    refute_equal existing, imported
    refute_equal @source, imported
    assert_equal 3, imported.people.count
    assert_equal 'Existing', imported.people.find_by!(is_primary: true).first_name
    assert_equal 'Source', imported.people.find(session[:current_person_id]).first_name
    assert_equal 2, existing.people.count
    assert_equal 1, @source.people.count
  end

  test 'signed-in import adds independent travelers without changing account identity or primary person' do
    account = users(:Sally)
    primary = account.people.find_by!(is_primary: true)
    count = account.people.count
    sign_in account
    get calculation_link_path(@token), headers: { 'Sec-Fetch-Site' => 'cross-site' }
    assert_equal count, account.people.count
    post claim_calculation_path, params: { token: @token, authenticity_token: form_csrf }
    assert_response :see_other
    assert_nil session[:guest_user_id]
    assert_equal account.id, request.env['warden'].user(:user).id
    assert_equal count + 1, account.people.count
    assert_equal primary, account.people.find_by!(is_primary: true)
    assert_equal 'Source', account.people.find(session[:current_person_id]).first_name
  end

  test 'following a malicious link before registration never imports attacker data' do
    get calculation_link_path(@token), headers: { 'Sec-Fetch-Site' => 'cross-site' }
    post user_registration_path(locale: :en), params: {
      authenticity_token: fresh_csrf,
      user: { first_name: 'Victim', last_name: 'Traveler', nationality_id: countries(:USA).id,
              email: 'claim-victim@example.com', password: 'password123', password_confirmation: 'password123' }
    }
    assert_response :redirect
    account = User.find_by!(email: 'claim-victim@example.com')
    assert_empty account.people.first.visits
    assert_nil @source.reload.calculation_claimed_at
    assert_equal 1, @source.people.first.visits.count
  end

  test 'failed import rolls back all copies and does not consume the link' do
    @source.people.first.visits.first.update_columns(entry_date: Date.today - 30.years)
    get calculation_link_path(@token)
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      post claim_calculation_path, params: { token: @token, authenticity_token: form_csrf }
    end
    assert_redirected_to root_path(locale: :en)
    assert_nil @source.reload.calculation_claimed_at
    assert_nil session[:guest_user_id]
  end

  test 'invalid expired and non-guest tokens cannot be imported' do
    tokens = [nil, ['invalid'], { invalid: 'token' }, 'invalid',
              @source.signed_id(purpose: :agent_calculation, expires_in: -1.second),
              users(:Sally).signed_id(purpose: :agent_calculation)]
    tokens.each do |token|
      assert_no_difference('User.count') do
        post claim_calculation_path, params: { token: token, authenticity_token: fresh_csrf }
      end
      assert_redirected_to root_path(locale: :en)
      assert_nil session[:guest_user_id]
    end
  end

  test 'oversized histories cannot cause an unbounded copy' do
    person = @source.people.first
    record = person.visits.first.attributes.except('id')
    Visit.insert_all!(Array.new(AgentCalculations::Claim::MAX_RECORDS) { record })
    get calculation_link_path(@token)
    assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
      post claim_calculation_path, params: { token: @token, authenticity_token: form_csrf }
    end
    assert_redirected_to root_path(locale: :en)
    assert_equal I18n.t('calculation_claim.too_large'), flash[:alert]
    assert_nil @source.reload.calculation_claimed_at
    assert_nil session[:guest_user_id]
  end

  private

  def create_source(first_name: 'Source')
    User.create!(guest: true, email: "source_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                 first_name: first_name, last_name: 'Traveler', nationality: countries(:USA)).tap do |guest|
      person = guest.people.find_by!(is_primary: true)
      person.visits.create!(country: countries(:Germany), entry_date: '2027-01-01', exit_date: '2027-01-05')
      person.visas.create!(visa_type: 'S', no_entries: 0, start_date: '2027-01-01', end_date: '2027-06-01')
    end
  end

  def form_csrf
    Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')['value']
  end

  def fresh_csrf
    get csrf_token_path(locale: :en), as: :json
    JSON.parse(response.body).fetch('token')
  end
end
