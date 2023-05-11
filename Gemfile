source 'https://rubygems.org'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '>= 6.0.0.rc2', '< 6.1'

# Use SCSS for stylesheets
gem 'sass-rails', '~> 5.1'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'
# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails'
# See https://github.com/sstephenson/execjs#readme for more supported runtimes
# gem 'therubyracer', platforms: :ruby

# Use jquery as the JavaScript library
gem 'jquery-rails'

# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.0'
# bundle exec rake doc:rails generates the API under doc/api.
gem 'sdoc', '~> 0.4.0', group: :doc

gem 'haml-rails', '~> 2.0.0'
gem 'bootstrap-sass', '~> 3.4.1'
gem "devise", ">= 4.9.2"
gem 'nokogiri'
gem 'geocoder'
gem 'omniauth-facebook'
gem 'puma'
gem 'amazon-ecs'
gem 'staccato'
gem 'pg'
gem 'mini_racer'
gem 'listen'
gem 'lamby'
gem "webpacker"
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Unicorn as the app server
# gem 'unicorn'

gem 'bourbon'
gem 'autoprefixer-rails'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development
group :production do
  
  gem 'rails_12factor'
end

group :development do
    gem 'web-console'
    gem 'capistrano',         require: false
    gem 'capistrano-rvm',     require: false
    gem 'capistrano-rails',   require: false
    gem 'capistrano-bundler', require: false
    gem 'capistrano3-puma',   require: false
    gem 'capistrano-rake',    require: false
end

group :development, :test do
  gem 'rails-controller-testing'
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring' , '~> 1.3.2'
  gem 'capybara'
  gem 'pry'
end
ruby '2.7.2'
