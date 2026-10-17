namespace :country_catalog do
  desc 'Generate localized, SQL-free country catalogue files'
  task generate: :environment do
    CountryCatalog::Generator.generate!
    puts "Generated country catalogues for #{I18n.available_locales.size} locales"
  end
end
