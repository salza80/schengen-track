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

  desc 'Insert missing people records'
  task fix_people: :environment do
    nationality = Country.find_by(country_code: "US")
    User.includes(:people).where(people: {user_id: nil}).each do |user|
      p = Person.new
      p.first_name = user.email
      puts user.email
      p.last_name = "last name"
      p.nationality = nationality
      user.people << p 
      user.save!
    end
  end

  desc 'fix multiple people'
  task fix_multi_people: :environment do
    Rails.logger.level = Logger::DEBUG
    ActiveRecord::Base.transaction do

      begin

        User.select("users.id, users.email").joins(:people).group("users.id").having("count(people.id) > ?", 1).each do |u|
          puts "user" + u.email
          firstname="", lastname=""
          visits=[]
          peopleIDs=[]

          u.people.each_with_index do |p, i|
            firstname=p.first_name unless p.first_name=="Guest"
            lastname=p.last_name unless p.last_name=="User"
            peopleIDs <<p.id
            puts "index" + i.to_s
            visits<<p.visits.count
            puts p.first_name
            puts p.last_name
            puts p.visits.count
          end
          maxid=0
          if visits[0] != 0
            puts "delete all but first person"
          else
            maxid = visits.each_with_index.max[1]
          end
          puts "keep indesx " + maxid.to_s 
          peopleIDs.each_with_index do |id, index|
            unless index==maxid
              puts "delted personid " + id.to_s
              Person.find(id).destroy
            end
          end

          unless firstname==""
             puts "update with firstname " + firstname
              u.people.first.first_name=firstname
              u.save
             
          end
          unless lastname ==""
              puts "update with lastname " + lastname
              u.people.first.last_name=lastname
              u.save
          end
        end

         User.select("users.id, users.email").joins(:people).group("users.id").having("count(people.id) > ?", 1)
         User.includes(:people).where(people: {user_id: nil}).count 

         raise ActiveRecord::Rollback
         User.select("users.id, users.email").joins(:people).group("users.id").having("count(people.id) > ?", 1)
         User.includes(:people).where(people: {user_id: nil}).count 
      end
    end
  end
end
