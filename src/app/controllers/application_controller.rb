require 'aws/book_query'

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  helper_method :current_user_or_guest_user, :amazon

  def amazon
    visits = current_user_or_guest_user.visits.find_by_date(Date.today + 1.month, Date.new(3000, 1, 1))
    search = ''
    unless visits.empty?
      search = visits.first.country.name +  ' '
    end

    search += 'europe'
    s = Aws::BookQuery.new(current_user_or_guest_user.nationality.country_code)
    s.query(search)
  end

  def current_user_or_guest_user
    current_user || guest_user
  end

  def redirect_with_cloudfront_support(path)
    @cloudfront_domain = ENV['CLOUDFRONT_DOMAIN']
    if @cloudfront_domain.present?
      full_url = "https://#{@cloudfront_domain}#{path}"
      redirect_to full_url
    else
      redirect_to path
    end
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
    user.first_name = 'Guest'
    user.last_name = 'User'
    user.nationality = default_guest_country
    user.save(validate: false)
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
