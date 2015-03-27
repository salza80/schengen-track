# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

Country.delete_all
Person.delete_all

c = Country.create(country_code: 'AU', name: 'Australia')
Person.create(first_name:'Sally', last_name:'Mclean', nationality: c)
Country.create(country_code: 'DE', name: 'Germany', schengen_start_date: '1/1/2010')
Country.create(country_code: 'CR', name: 'Croatia', schengen_start_date: '1/1/2016')
