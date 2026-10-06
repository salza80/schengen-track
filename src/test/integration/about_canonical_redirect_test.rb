require 'test_helper'

class AboutCanonicalRedirectTest < ActionDispatch::IntegrationTest
  test 'citizenship selector has a stable visible label and no selection on the generic page' do
    get '/en/about'

    assert_response :success
    assert_select 'label[for="user_nationality_id"]', text: 'Select your country of citizenship'
    assert_select '#user_nationality_id', count: 1
    assert_select '#user_nationality_id option[selected]:not([value=""])', count: 0
  end

  test 'about page has a matching canonical and one alternate per locale' do
    get '/en/about'

    assert_response :success
    assert_select 'link[rel="canonical"]', count: 1 do |links|
      assert_equal 'https://www.example.com/about', links.first['href']
      assert_nil links.first['hreflang']
    end
    assert_select 'link[rel="alternate"][hreflang="en"][href="https://www.example.com/about"]', count: 1
    assert_select 'link[rel="alternate"][hreflang="de"][href="https://www.example.com/de/about"]', count: 1
    assert_select 'link[rel="alternate"][hreflang="x-default"][href="https://www.example.com/about"]', count: 1
    assert_select 'link[rel="alternate"]', count: I18n.available_locales.size + 1
    assert_select 'meta[property="og:url"][content="https://www.example.com/about"]', count: 1

    about_page_schema = json_ld_objects.find { |item| item['@type'] == 'AboutPage' }
    faq_schema = json_ld_objects.find { |item| item['@type'] == 'FAQPage' }
    assert_equal 'https://schengen-calculator.com/about', about_page_schema['url']
    assert_equal 'https://schengen-calculator.com/about#webpage', about_page_schema['@id']
    assert_equal 'https://schengen-calculator.com/about#faq', faq_schema['@id']
  end

  test 'localized about page is self-canonical' do
    get '/de/about'

    assert_response :success
    assert_select 'link[rel="canonical"][href="https://www.example.com/de/about"]', count: 1
    assert_select 'link[rel="alternate"][hreflang="en"][href="https://www.example.com/about"]', count: 1
    assert_select 'meta[property="og:url"][content="https://www.example.com/de/about"]', count: 1
  end

  test 'registration instructions distinguish new registration from existing account login' do
    get '/en/about'

    assert_response :success
    assert_select '.step-description', text: /registration transfers every guest traveler/
    assert_select '.step-description', text: /Logging in to an existing account keeps its data separate/
  end

  test 'citizenship selector precedes the country information and selects the page country in every locale' do
    I18n.available_locales.each do |locale|
      assert_no_difference(['User.count', 'Person.count']) { get "/#{locale}/about/American" }
      assert_response :success
      assert_select 'label[for="user_nationality_id"]', text: I18n.t('about.about.nationality_section.select_prompt', locale: locale)
      assert_select '#user_nationality_id', count: 1
      assert_select '#user_nationality_id option[selected]', count: 1
      assert_select '#user_nationality_id option[value="American"][selected]'
      document = Nokogiri::HTML(response.body)
      selector = document.at_css('#user_nationality_id')
      heading = I18n.with_locale(locale) do
        I18n.t('about.nationality.tourist_travel_requirements_title',
               nationality_plural: Country.find_by(country_code: 'US').nationality_plural)
      end
      # The first following heading belongs to the nationality information.
      following_heading = selector.xpath('following::h3').first
      assert following_heading
      assert_equal heading, following_heading.text.strip
      assert_includes response.headers['Cache-Control'], 'public'
      assert_nil response.headers['Set-Cookie']
    end
  end

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
