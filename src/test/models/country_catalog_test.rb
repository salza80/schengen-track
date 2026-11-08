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

  test 'unsupported locale paths use the default catalogue' do
    ['../en', 'en/../../Gemfile', 'en\\..\\Gemfile'].each do |locale|
      assert_equal CountryCatalog.all(locale: :en), CountryCatalog.all(locale: locale)
    end
  end

  test 'plural nationality slugs retain their canonical compatibility' do
    country = CountryCatalog.find_by_nationality_slug('Americans')

    assert_equal 'US', country.country_code
    assert_equal 'American', country.nationality
  end

  test 'search options include all countries and use localized names without SQL' do
    options = nil
    queries = capture_database_queries { options = CountryCatalog.country_options(locale: :de) }
    assert_empty queries
    assert_equal CountryCatalog.all(locale: :de).map(&:country_code).sort, options.map { |option| option[:country_code] }.sort
    assert_equal({ country_code: 'DE', name: 'Deutschland' }, options.find { |option| option[:country_code] == 'DE' })
    assert_equal({ country_code: 'IN', name: 'Indien' }, options.find { |option| option[:country_code] == 'IN' })
  end
end
