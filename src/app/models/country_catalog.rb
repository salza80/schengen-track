# frozen_string_literal: true

require 'json'

# Immutable, file-backed presentation data for rendering public pages without
# touching Active Record. Entries intentionally resemble the read-only parts of
# Country, but they must never be assigned to an Active Record association.
# Resolve their stable country_code to Country only at a persistence boundary.
class CountryCatalog
  CATALOG_DIRECTORY = Rails.root.join('config', 'country_catalog').freeze

  # Read-only Country-compatible value object. Its translated fields belong to
  # the locale of the catalogue from which it was loaded.
  Entry = Struct.new(
    :country_code,
    :base_name,
    :name,
    :base_nationality,
    :localized_nationality,
    :nationality_plural,
    :continent_code,
    :schengen_start_date,
    :EU_member_state,
    :visa_required,
    :additional_visa_waiver,
    keyword_init: true
  ) do
    def localized_name(_locale = I18n.locale)
      name
    end

    def nationality
      base_nationality
    end

    def nationality_english
      base_nationality
    end

    def nationality_translated
      localized_nationality
    end

    def schengen?(use_date = Time.zone.now)
      schengen_start_date.present? && schengen_start_date <= use_date.to_date
    end
  end

  # Read-only option value used by the public travel form.
  Continent = Struct.new(:code, :name, keyword_init: true)

  class << self
    def all(locale: I18n.locale)
      catalog(locale)[:countries]
    end

    def continents(locale: I18n.locale)
      catalog(locale)[:continents]
    end

    def outside_schengen(locale: I18n.locale)
      all(locale: locale).reject { |country| country.visa_required == 'F' }
    end

    def for_continent(code, locale: I18n.locale)
      all(locale: locale).select { |country| country.continent_code == code }
    end

    def find_by_code(code, locale: I18n.locale)
      return if code.blank?

      catalog(locale)[:countries_by_code][code.to_s.upcase]
    end

    def find_by_nationality_slug(slug, locale: I18n.locale)
      normalized_slugs = [slug, slug.to_s.singularize].map { |value| normalize_slug(value) }.uniq
      all(locale: locale).find do |country|
        candidates = [country.base_nationality, country.base_name]
        candidates.any? { |candidate| normalized_slugs.include?(normalize_slug(candidate)) }
      end
    end

    def country_options(locale: I18n.locale)
      all(locale: locale).map do |country|
        {
          country_code: country.country_code,
          name: country.name,
          continent_code: country.continent_code
        }
      end
    end

    def reset!
      @catalogs = {}
    end

    private

    def catalog(locale)
      available_locales = I18n.available_locales.map(&:to_s)
      normalized_locale = available_locales.include?(locale.to_s) ? locale.to_s : I18n.default_locale.to_s
      @catalogs ||= {}
      @catalogs[normalized_locale] ||= load_catalog(normalized_locale)
    end

    def load_catalog(locale)
      payload = JSON.parse(File.read(CATALOG_DIRECTORY.join("#{locale}.json")))
      countries = payload.fetch('countries').map do |country|
        Entry.new(
          country_code: country.fetch('country_code'),
          base_name: country.fetch('base_name'),
          name: country.fetch('name'),
          base_nationality: country.fetch('base_nationality'),
          localized_nationality: country.fetch('localized_nationality'),
          nationality_plural: country.fetch('nationality_plural'),
          continent_code: country.fetch('continent_code'),
          schengen_start_date: country['schengen_start_date'].present? ? Date.iso8601(country['schengen_start_date']) : nil,
          EU_member_state: country.fetch('EU_member_state'),
          visa_required: country.fetch('visa_required'),
          additional_visa_waiver: country.fetch('additional_visa_waiver')
        ).freeze
      end.sort_by { |country| country.name.downcase }
      continents = payload.fetch('continents').map do |continent|
        Continent.new(code: continent.fetch('code'), name: continent.fetch('name')).freeze
      end

      {
        countries: countries.freeze,
        countries_by_code: countries.index_by(&:country_code).freeze,
        continents: continents.freeze
      }.freeze
    end

    def normalize_slug(value)
      value.to_s.downcase.tr(' ', '_')
    end
  end
end
