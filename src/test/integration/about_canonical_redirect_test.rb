require 'test_helper'

class AboutCanonicalRedirectTest < ActionDispatch::IntegrationTest
  test 'redirects lowercase nationality to canonical stored slug' do
    get '/about/american'

    assert_response :moved_permanently
    assert_redirected_to '/about/American'
  end

  test 'ignores query locale when redirecting to canonical nationality slug' do
    get '/about/american', params: { locale: 'bad-locale' }

    assert_response :moved_permanently
    assert_redirected_to '/about/American'
  end

  test 'uses route locale instead of query locale for canonical nationality slug' do
    get '/fr/about/american', params: { locale: 'bad-locale' }

    assert_response :moved_permanently
    assert_redirected_to '/fr/about/American'
  end

  test 'ignores invalid query locale when switching locale' do
    get '/about', params: { locale: 'bad-locale' }

    assert_response :success
    assert_includes response.body, I18n.t('about.about.title', locale: :en)
  end

  test 'about structured data breadcrumbs use route locale labels' do
    get '/fr/about'

    assert_response :success

    about_page_schema = json_ld_objects.find { |item| item['@type'] == 'AboutPage' }
    breadcrumb_items = about_page_schema.dig('breadcrumb', 'itemListElement')

    assert_equal 'Accueil', breadcrumb_items.first['name']
    assert_equal 'À propos', breadcrumb_items.second['name']
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

  private

  def json_ld_objects
    Nokogiri::HTML(response.body).css('script[type="application/ld+json"]').flat_map do |script|
      document = JSON.parse(script.text)
      document.is_a?(Array) ? document : [document]
    end
  end
end
