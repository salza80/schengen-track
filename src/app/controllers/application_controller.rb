require 'aws/book_query'
require 'securerandom'

class ApplicationController < ActionController::Base
  before_action :set_cache_cookie, unless: :task_controller?
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  #protect_from_forgery with: :exception
  skip_before_action :verify_authenticity_token

  helper_method :current_user_or_guest_user, :amazon
  around_action :switch_locale

  def switch_locale(&action)
    locale = params[:locale] || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

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
  
  private

  def task_controller?
    controller_name == 'tasks'
  end

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

  private

  def set_cache_cookie
    guest_value = current_user_or_guest_user.is_guest? ? 'true' : SecureRandom.hex(16)
    cookies[:cache_country_guest] = {
      value: current_user_or_guest_user.nationality.country_code + "_" + guest_value,
      expires: 1.month.from_now,
      httponly: true,
      secure: Rails.env.production?
    }
  end
end
