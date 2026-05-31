require 'test_helper'

class AboutCanonicalRedirectTest < ActionDispatch::IntegrationTest
  test 'redirects lowercase nationality to canonical stored slug' do
    get '/about/american'

    assert_response :moved_permanently
    assert_redirected_to '/about/American'
  end

  test 'redirects space separated nationality to canonical underscore slug' do
    Country.create!(
      name: 'Saudi Arabia',
      nationality: 'Saudi Arabian',
      country_code: 'SA',
      continent: continents(:Asia),
      visa_required: 'A',
      EU_member_state: false,
      additional_visa_waiver: false
    )

    get '/ar/about/Saudi%20Arabian'

    assert_response :moved_permanently
    assert_redirected_to '/ar/about/Saudi_Arabian'
  end
end
