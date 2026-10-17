# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'nokogiri'

class CountryCatalog
  # Build-time generator kept separate from the runtime catalogue reader. It
  # turns the authoritative XML and locale files into immutable JSON shipped in
  # the Lambda image; serving a request never invokes this class.
  class Generator
    COUNTRIES_SOURCE = Rails.root.join('db', 'data', 'countries.xml').freeze
    CONTINENTS_SOURCE = Rails.root.join('db', 'data', 'continent.xml').freeze

    class << self
      def generate!
        FileUtils.mkdir_p(CountryCatalog::CATALOG_DIRECTORY)
        source_countries = parse_country_source
        source_continents = parse_continent_source

        I18n.available_locales.each do |locale|
          payload = I18n.with_locale(locale) do
            {
              version: 1,
              locale: locale.to_s,
              continents: source_continents.map { |continent| localized_continent_payload(continent) },
              countries: source_countries.map { |country| localized_country_payload(country) }
            }
          end
          write_catalog(locale, payload)
        end

        CountryCatalog.reset!
      end

      private

      def write_catalog(locale, payload)
        path = CountryCatalog::CATALOG_DIRECTORY.join("#{locale}.json")
        File.write(path, JSON.pretty_generate(payload) + "\n")
      end

      def parse_country_source
        source_records(COUNTRIES_SOURCE).map do |record|
          {
            country_code: record.at_xpath('country_code').text,
            base_name: record.at_xpath('name').text,
            base_nationality: record.at_xpath('nationality').text,
            continent_code: record.at_xpath('continent_code').text,
            schengen_start_date: record.at_xpath('schengen_start_date').text.presence,
            EU_member_state: boolean_value(record, 'EU_memeber_state'),
            visa_required: record.at_xpath('visa_required').text,
            additional_visa_waiver: boolean_value(record, 'additional_visa_waiver')
          }
        end
      end

      def parse_continent_source
        source_records(CONTINENTS_SOURCE).map do |record|
          {
            code: record.at_xpath('continent_code').text,
            base_name: record.at_xpath('name').text
          }
        end
      end

      def source_records(path)
        Nokogiri::XML(File.read(path)).xpath('//record')
      end

      def boolean_value(record, field)
        ActiveModel::Type::Boolean.new.cast(record.at_xpath(field).text)
      end

      def localized_country_payload(country)
        code = country.fetch(:country_code)
        country.merge(
          name: I18n.t("#{code}_name", default: country.fetch(:base_name)),
          localized_nationality: I18n.t("#{code}_nationality", default: country.fetch(:base_nationality)),
          nationality_plural: I18n.t("#{code}_nationality_plural", default: country.fetch(:base_nationality))
        )
      end

      def localized_continent_payload(continent)
        name = continent.fetch(:base_name)
        {
          code: continent.fetch(:code),
          name: I18n.t("continents.#{name.downcase.tr(' ', '_')}", default: name)
        }
      end
    end
  end
end
