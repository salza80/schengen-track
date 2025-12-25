require 'nokogiri'
# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

User.destroy_all
Country.delete_all
Continent.delete_all



f = File.open(File.join(Rails.root, 'db/data', 'continent.xml'))
continents = Nokogiri::XML(f)

continents.xpath('//record').each do |cont|
  Continent.create(continent_code: cont.xpath('continent_code').text, name: cont.xpath('name').text)
end
f.close

f = File.open(File.join(Rails.root, 'db/data', 'countries.xml'))
countries = Nokogiri::XML(f)

countries.xpath('//record').each do |c|
  cont = Continent.find_by(continent_code: c.xpath('continent_code').text)
  Country.create(country_code: c.xpath('country_code').text,
                   name: c.xpath('name').text,
                   nationality: c.xpath('nationality').text,
                   schengen_start_date: c.xpath('schengen_start_date').text,
                   EU_member_state: c.xpath('EU_memeber_state').text,
                   visa_required: c.xpath('visa_required').text,
                   additional_visa_waiver: c.xpath('additional_visa_waiver').text,
                   affiliate_booking_html: c.xpath('affiliate_booking_html').text,
                   continent: cont
                )
end
f.close

c = Country.find_by(country_code: 'AU')
user = User.new(email:'smclean17@hotmail.com', password:'password', password_confirmation: 'password', first_name:'Sally', last_name:'Mclean', nationality: c)
user.save!
de = Country.find_by(country_code: 'DE')
cz = Country.find_by(country_code: 'CZ')
Visit.create(entry_date: '2013/1/1', exit_date: '2013/2/1', country: de, user: user)
Visit.create(entry_date: '2013/4/2', exit_date: '2013/5/2', country: cz, user: user)
