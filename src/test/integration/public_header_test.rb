require 'test_helper'

class PublicHeaderTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'public pages never create guest accounts or embed session-specific markup' do
    paths = %w[/ /en /fr /ar /about /about/American /blog/extended-schengen-stay /privacy /disclaimer /datadeletion]
    paths.each do |path|
      assert_no_difference(['User.count', 'Person.count']) { get path }
      assert_response :success
      assert_includes response.headers['Cache-Control'], 'public'
      assert_nil response.headers['Set-Cookie']
      assert_select '#public-user-menu', count: 1
      assert_select '#personDropdown, meta[name="csrf-token"], input[name="authenticity_token"]', count: 0
    end
  end

  test 'public HTML remains identical for a signed-in visitor' do
    get '/fr/about'
    anonymous_body = response.body
    sign_in users(:Sally)
    get '/fr/about'
    assert_equal anonymous_body, response.body
    assert_not_includes response.body, users(:Sally).full_name
  end

  test 'header endpoint never creates a guest for a new visitor' do
    assert_no_difference(['User.count', 'Person.count']) { get '/en/session_header' }
    assert_response :no_content
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_nil cookies['_schengen_track_session']
  end

  test 'header endpoint does not query the database without calculator state' do
    database_queries = capture_database_queries do
      get '/en/session_header'
    end

    assert_response :no_content
    assert_empty database_queries
  end

  test 'nationality-only calculator state keeps its hint without rendering a person menu' do
    patch calculator_preferences_path(locale: :en), params: {
      nationality_code: 'IN',
      destination: 'trips'
    }
    follow_redirect!
    assert_equal '1', cookies[:has_calculator_session]

    assert_no_difference(['User.count', 'Person.count']) { get '/en/session_header' }

    assert_response :no_content
    refute_match(/has_calculator_session=;.*max-age=0/, response_cookie_headers)
  end

  test 'existing guests receive only their own menu and stale sessions create nothing' do
    guest = establish_guest_session
    person = guest.people.first
    person.update!(first_name: 'Header', last_name: 'Guest')

    assert_no_difference(['User.count', 'Person.count']) { get '/fr/session_header' }
    assert_response :success
    data = response.parsed_body
    assert_includes data['html'], 'Header Guest'
    assert_includes data['html'], "/fr/people/#{person.id}/edit"
    assert_not_includes data['html'], "/people/#{people(:sally_person).id}/edit"
    assert data['csrf_token'].present?
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal '1', cookies[:has_calculator_session]

    guest.destroy!
    assert_no_difference(['User.count', 'Person.count']) { get '/en/session_header' }
    assert_response :no_content
    assert_match(/has_calculator_session=;.*max-age=0/, response_cookie_headers)
    assert_not_includes response_cookie_headers, '_schengen_track_session='
  end

  test 'signed-in header includes correct person links and logout form' do
    sign_in users(:Sally)
    get '/en/session_header'
    assert_response :success
    html = response.parsed_body['html']
    assert_includes html, users(:Sally).full_name
    assert_includes html, "/en/people/#{people(:sally_person).id}/edit"
    assert_includes html, 'logout-form'
    fragment = Nokogiri::HTML5.fragment(html)
    assert_equal 'post', fragment.at_css('#logout-form')['method']
    assert_equal 'delete', fragment.at_css('#logout-form input[name="_method"]')['value']
    assert fragment.at_css('#logout-form button[type="submit"]')
    assert_empty fragment.css('[onclick]')
    assert_includes response.headers['Cache-Control'], 'no-store'
  end

  test 'a guest without people is not repaired by the header request' do
    guest = establish_guest_session
    guest.people.delete_all
    assert_no_difference(['User.count', 'Person.count']) { get '/en/session_header' }
    assert_response :no_content
  end

  test 'invalid calculation alerts are delivered once outside the public cache' do
    get '/calculations/invalid-token'
    assert_response :redirect
    assert_includes response_cookie_headers, 'has_flash_message=1;'
    follow_redirect!
    message = I18n.t('calculation_claim.invalid')
    assert_not_includes response.body, message
    assert_includes response.headers['Cache-Control'], 'public'

    assert_no_difference(['User.count', 'Person.count']) { get '/en/session_header' }
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal [{ 'type' => 'alert', 'text' => message }], response.parsed_body['messages']
    refute response.parsed_body.key?('notice_html')
    get '/en/session_header'
    assert_response :no_content
  end

  test 'account deletion confirmation works without a surviving user or guest' do
    sign_in users(:Sally)
    delete '/en/my_details'
    assert_response :redirect
    assert_match(/has_calculator_session=;.*max-age=0/, response_cookie_headers)
    assert_includes response_cookie_headers, 'has_flash_message=1;'
    follow_redirect!
    message = 'Your account has been successfully deleted.'
    assert_not_includes response.body, message

    cookies[:has_flash_message] = '1'
    assert_no_difference(['User.count', 'Person.count']) { get '/en/session_header' }
    assert_response :success
    assert_equal [{ 'type' => 'notice', 'text' => message }], response.parsed_body['messages']
    assert_nil response.parsed_body['html']
    assert_nil response.parsed_body['csrf_token']
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_match(/has_flash_message=;.*max-age=0/, response_cookie_headers)
    get '/en/session_header'
    assert_response :no_content
  end

  test 'person names remain escaped in menu HTML and unencoded in one-time flash text' do
    sign_in users(:Sally)
    person = people(:sally_person)
    person.update!(first_name: '<img src=x onerror="alert(1)">', last_name: '& Friend')

    post set_current_person_path(person, locale: :en), headers: { 'HTTP_REFERER' => '/en/about' }
    assert_response :redirect
    get '/en/session_header'
    assert_response :success
    data = response.parsed_body
    assert_equal [{ 'type' => 'notice', 'text' => "Switched to #{person.full_name}" }], data['messages']
    refute data.key?('notice_html')
    menu = Nokogiri::HTML5.fragment(data.fetch('html'))
    assert_equal person.full_name, menu.at_css('.person-name').text
    assert_empty menu.css('img, script, [onerror]')

    get '/en/session_header'
    assert_equal [], response.parsed_body['messages']
  end

  test 'primary-person notices are plain text and remain escaped on server-rendered pages' do
    sign_in users(:Sally)
    person = people(:sally_person_alt)
    person.update!(first_name: '<svg onload="alert(1)">', last_name: '& Friend')

    post make_primary_person_path(person, locale: :en)
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_select '.alert-success', text: "#{person.full_name} is now your primary person"
    assert_select '.alert-success svg, .alert-success [onload]', count: 0
  end

  private

  def establish_guest_session
    guest = User.create!(
      guest: true,
      email: "header-guest-#{SecureRandom.hex(6)}@example.com",
      password: 'password',
      first_name: 'Guest',
      last_name: 'User',
      nationality: countries(:USA)
    )
    guest = import_guest_calculation(guest)
    follow_redirect!
    guest
  end
end
