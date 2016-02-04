require 'nokogiri'
namespace :db do
  desc 'Update Country and Continent Data.'
  task update_countries: :environment do

    f = File.open(File.join(Rails.root, 'db/data', 'continent.xml'))
    continents = Nokogiri::XML(f)

    continents.xpath('//record').each do |c|
      cont = Continent.find_or_create_by(
        continent_code: c.xpath('continent_code').text
      )
      cont.name = c.xpath('name').text
      cont.save!
    end
    f.close

    f = File.open(File.join(Rails.root, 'db/data', 'countries.xml'))
    countries = Nokogiri::XML(f)

    countries.xpath('//record').each do |c|
      cont = Continent.find_by(continent_code: c.xpath('continent_code').text)
      country = Country.find_or_create_by(
        country_code: c.xpath('country_code').text
      )
      
      country.name =  c.xpath('name').text
      country.nationality = c.xpath('nationality').text
      country.schengen_start_date = c.xpath('schengen_start_date').text
      country.EU_member_state = c.xpath('EU_memeber_state').text
      country.visa_required = c.xpath('visa_required').text
      country.old_schengen_calc = c.xpath('old_schengen_calc').text
      country.additional_visa_waiver = c.xpath('additional_visa_waiver').text
      country.affiliate_booking_html = c.xpath('affiliate_booking_html').text
      country.continent = cont
      
      country.save!
    end
    f.close
  end
end



