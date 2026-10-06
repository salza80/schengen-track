require 'aws/book_query'

class ApplicationController < ActionController::Base
  CANONICAL_SITE_URL = 'https://schengen-calculator.com'.freeze
  SEO_LOCALE_PREFIX_PATTERN = %r{\A/(?:#{Regexp.union(I18n.available_locales.map(&:to_s))})(?=/|\z)}.freeze
  SCHENGEN_AREA_SOURCE_URL = 'https://home-affairs.ec.europa.eu/policies/schengen/schengen-area_en'.freeze
  VISA_REQUIREMENTS_SOURCE_URL = 'https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:02018R1806-20251230'.freeze
  ETIAS_FAQ_SOURCE_URL = 'https://travel-europe.europa.eu/en/etias/faq'.freeze
  ETIAS_OVERVIEW_SOURCE_URL = 'https://travel-europe.europa.eu/en/etias/about-etias/what-is-etias'.freeze
  ETIAS_FEE_SOURCE_URL = 'https://travel-europe.europa.eu/en/etias/about-etias/news-corner/ETIAS-will-cost-EUR-20'.freeze

  BLOG_OFFICIAL_SOURCE_URLS = [
    SCHENGEN_AREA_SOURCE_URL,
    VISA_REQUIREMENTS_SOURCE_URL
  ].freeze

  ABOUT_OFFICIAL_SOURCE_URLS = [
    SCHENGEN_AREA_SOURCE_URL,
    VISA_REQUIREMENTS_SOURCE_URL,
    ETIAS_FAQ_SOURCE_URL,
    ETIAS_OVERVIEW_SOURCE_URL,
    ETIAS_FEE_SOURCE_URL
  ].freeze

  before_action :restore_guest_calculation
  before_action :sync_session_hint_cookie, unless: :task_controller?
  after_action :set_flash_hint
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  # skip_before_action :verify_authenticity_token

  helper_method :current_user_or_guest_user, :current_person, :anonymous_calculator?,
                :calculator_nationality_selected?, :amazon, :seo_canonical_path
  around_action :switch_locale

  def default_url_options
    { locale: I18n.locale }
  end

  private

  def organization_schema(include_logo: false)
    schema = {
      "@type" => "Organization",
      "@id" => "#{CANONICAL_SITE_URL}/#organization",
      "name" => I18n.t('common.schengen_calculator'),
      "url" => "#{CANONICAL_SITE_URL}/"
    }

    schema["logo"] = image_object_schema('med.png') if include_logo

    schema
  end

  def image_object_schema(asset_name)
    {
      "@type" => "ImageObject",
      "url" => canonical_asset_url(asset_name)
    }
  end

  def canonical_url(path = '/')
    normalized_path = path.to_s
    normalized_path = "/#{normalized_path}" unless normalized_path.start_with?('/')
    "#{CANONICAL_SITE_URL}#{normalized_path}"
  end

  def seo_canonical_path(path = request.path, locale: I18n.locale)
    page_path = path.to_s.sub(SEO_LOCALE_PREFIX_PATTERN, '').presence || '/'
    return page_path if locale.to_sym == I18n.default_locale.to_sym

    "/#{locale}#{page_path == '/' ? '' : page_path}"
  end

  def canonical_asset_url(asset_name)
    "#{CANONICAL_SITE_URL}#{view_context.asset_path(asset_name)}"
  end

  def absolute_asset_url(asset_name)
    "https://#{request.host_with_port}#{view_context.asset_path(asset_name)}"
  end

  def switch_locale(&action)
    locale = route_locale || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def route_locale
    raw_locale = request.path_parameters[:locale].presence
    I18n.available_locales.find { |locale| locale.to_s == raw_locale.to_s }
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
    return @current_user_or_guest_user if defined?(@current_user_or_guest_user)

    @current_user_or_guest_user = current_user || guest_user
  end

  def current_person
    return @current_person if defined?(@current_person)

    user = current_user_or_guest_user
    person = Person.find_by(id: session[:current_person_id], user: user) if user && session[:current_person_id]
    person ||= user.people.find_by(is_primary: true) if user
    person ||= user.people.first if user

    @current_person = person || draft_calculator_person
  end

  def anonymous_calculator?
    current_user_or_guest_user.nil?
  end

  def calculator_nationality_selected?
    selected_calculator_nationality.present?
  end
  
  private

  def task_controller?
    controller_name == 'tasks'
  end

  def restore_guest_calculation
    return if params[:guest_calculation].blank?
    return unless request.get?

    user = User.find_signed(params[:guest_calculation], purpose: :agent_calculation)
    return unless user&.is_guest?

    session[:guest_user_id] = user.id
    person = user.people.where(is_primary: true).first || user.people.first
    session[:current_person_id] = person&.id

    return redirect_to clean_guest_calculation_url(person)
  end

  def clean_guest_calculation_url(person)
    cleaned_params = request.query_parameters.except('guest_calculation')

    if controller_name == 'days' && cleaned_params.slice('year', 'month', 'day').empty?
      first_entry = person&.visits&.minimum(:entry_date)
      if first_entry
        cleaned_params['year'] = first_entry.year
        cleaned_params['month'] = first_entry.month
        cleaned_params['day'] = first_entry.day
      end
    end

    cleaned_params.present? ? "#{request.path}?#{cleaned_params.to_query}" : request.path
  end

  def guest_user
    return unless session[:guest_user_id]

    user = User.find_by(id: session[:guest_user_id], guest: true)
    unless user
      session.delete(:guest_user_id)
      session.delete(:current_person_id)
    end
    user
  end

  def draft_calculator_person
    @draft_calculator_person ||= Person.new(
      first_name: 'Guest',
      last_name: 'User',
      nationality: calculator_nationality
    )
  end

  def calculator_nationality
    selected_calculator_nationality || default_guest_country
  end

  def selected_calculator_nationality
    return @selected_calculator_nationality if defined?(@selected_calculator_nationality)

    @selected_calculator_nationality = Country.find_by(id: session[:calculator_nationality_id])
  end

  def render_calculator_nationality_required(open_trip: false)
    redirect_options = { locale: I18n.locale }
    redirect_options[:open] = 'trip' if open_trip
    redirect_path = visits_path(redirect_options)
    message = t('common.choose_nationality')

    respond_to do |format|
      format.html { redirect_to redirect_path, alert: message }
      format.json { render json: { error: message }, status: :unprocessable_entity }
      format.js { render js: "window.location.assign(#{redirect_path.to_json});" }
    end
  end

  def establish_guest_session(user, person)
    session[:guest_user_id] = user.id
    session[:current_person_id] = person.id
    session.delete(:calculator_nationality_id)
    @current_user_or_guest_user = user
    @current_person = person
    sync_session_hint_cookie
  end

  def require_calculator_account!
    redirect_to visits_path(locale: I18n.locale) if anonymous_calculator?
  end

  def require_calculator_record_account!
    raise ActiveRecord::RecordNotFound if anonymous_calculator?
  end

  def set_private_calculator_cache
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Vary'] = 'Cookie'
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

  def sync_session_hint_cookie
    user = current_user_or_guest_user
    if user || selected_calculator_nationality
      set_session_hint
    elsif cookies[:has_calculator_session].present?
      clear_session_hint
    end
  end

  def set_session_hint
    # Public-page JavaScript uses this non-sensitive hint, never as authorization.
    cookies[:has_calculator_session] = { value: '1', path: '/', same_site: :lax,
                                        secure: Rails.env.production? }
  end

  def clear_session_hint
    cookies.delete(:has_calculator_session, path: '/')
  end

  def set_flash_hint
    # Public HTML must neither inspect nor consume session-specific messages.
    return if @public_static_page

    if response.redirect? && (flash[:notice].present? || flash[:alert].present?)
      cookies[:has_flash_message] = { value: '1', path: '/', same_site: :lax,
                                     secure: Rails.env.production? }
    elsif !response.redirect?
      cookies.delete(:has_flash_message, path: '/')
    end
  end
end
