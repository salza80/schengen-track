require 'aws/book_query'

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  helper_method :current_person, :amazon

  def current_person
    current_user_or_guest_user.people.first
  end

  def amazon
    visits = current_person.visits.find_by_date(Date.today, Date.new(3000, 1, 1))
    search = ''
    unless visits.nil?
      visits.each do |visit|
        search += visit.country.name + ' '
      end
    end
    search += 'europe'
    s = Aws::BookQuery.new(current_person.nationality.country_code)
    s.query(search)
  end

  def current_user_or_guest_user
    current_user || guest_user
  end

  private

  def guest_user
    user = User.find_by_id(session[:guest_user_id])
    unless user
      user = create_guest_user
      session[:guest_user_id] = user.id
    end
    user
  end

  def create_guest_user
    user = User.new
    user.guest = true
    user.email = "guest_#{Time.now.to_i}#{rand(99)}@example.com"
    user.password = 'password'
    user.save(validate: false)

    p = user.people.build(first_name: 'Guest', last_name: 'User', nationality: default_guest_country)
    p.save(validate: false)
    user.reload
    user
  end

  def default_guest_country
    # country = request.location.data[:country_name]
    # c = Country.find_by(name: country)
    # c || Country.find_by(country_code: 'US')
    Country.find_by(country_code: 'US')

  end

  def extract_locale_from_accept_language_header
    # code = request.env['HTTP_ACCEPT_LANGUAGE']
    # puts code
    # code ? code.scan(/^[a-z]{2}/).first.upcase : 'AU'
  end
end
