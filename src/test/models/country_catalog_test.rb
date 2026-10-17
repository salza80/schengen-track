require 'test_helper'

class CountryCatalogTest < ActiveSupport::TestCase
  test 'generated catalogues contain every source country in every locale' do
    source = Nokogiri::XML(File.read(Rails.root.join('db/data/countries.xml')))
    source_codes = source.xpath('//record/country_code').map(&:text).sort

    I18n.available_locales.each do |locale|
      assert_equal source_codes, CountryCatalog.all(locale: locale).map(&:country_code).sort
    end
  end

  test 'catalogue lookups execute no SQL' do
    CountryCatalog.reset!
    entry = nil
    queries = capture_database_queries { entry = CountryCatalog.find_by_code('US', locale: :de) }

    assert_empty queries
    assert_equal 'US', entry.country_code
    assert_equal 'Vereinigte Staaten', entry.name
  end

  test 'nationality slugs resolve to the canonical static entry' do
    country = CountryCatalog.find_by_nationality_slug('american', locale: :fr)

    assert_equal 'US', country.country_code
    assert_equal 'American', country.nationality_english
    assert_equal 'États-Unis', country.name
  end

  test 'plural nationality slugs retain their canonical compatibility' do
    country = CountryCatalog.find_by_nationality_slug('Americans')

    assert_equal 'US', country.country_code
    assert_equal 'American', country.nationality
  end

  test 'continent filtering returns catalogue entries without database relations' do
    european_countries = CountryCatalog.for_continent('EU')

    assert_includes european_countries.map(&:country_code), 'DE'
    assert european_countries.all? { |country| country.continent_code == 'EU' }
  end

  test 'continents are localized in generated catalogues' do
    europe = CountryCatalog.continents(locale: :de).find { |continent| continent.code == 'EU' }

    assert_equal 'Europa', europe.name
  end
end
