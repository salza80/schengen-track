# frozen_string_literal: true

# Public controllers never resolve sessions. Separate private routes validate
# signed calculator state before doing any calculator work.
module CalculatorIndexCache
  extend ActiveSupport::Concern

  DEFAULT_EDGE_TTL = 30.days.to_i
  STALE_TTL = 7.days.to_i

  included do
    prepend_before_action :prepare_calculator_index_cache, only: :index
  end

  private

  def prepare_calculator_index_cache
    if params[:guest_calculation].present?
      restore_guest_calculation
      return
    end

    unless public_calculator_index?
      set_private_calculator_cache
      unless active_calculator_context?
        path = controller_name == 'days' ? days_path(calculator_redirect_parameters) : visits_path(calculator_redirect_parameters)
        redirect_to path, status: :see_other, allow_other_host: false
      end
      return
    end

    unless request.format.html?
      set_private_calculator_cache
      options = calculator_redirect_parameters.merge(format: request.format.symbol)
      path = controller_name == 'days' ? private_days_path(options) : private_visits_path(options)
      redirect_to path, status: :see_other, allow_other_host: false
      return
    end

    @public_static_page = true
    @public_calculator_page = true
    request.session_options[:skip] = true
    response.headers['Cache-Control'] = public_calculator_cache_control
  end

  def public_calculator_index?
    false
  end

  def calculator_redirect_parameters
    params.permit(:year, :month, :day, :open).to_h.symbolize_keys.merge(locale: route_locale || I18n.default_locale)
  end

  def public_calculator_cache_control
    fresh_ttl = configured_fresh_ttl
    fresh_ttl, stale_ttl = cache_durations_before_year_boundary(fresh_ttl)
    "public, max-age=0, s-maxage=#{fresh_ttl}, stale-while-revalidate=#{stale_ttl}, stale-if-error=#{stale_ttl}"
  end

  def configured_fresh_ttl
    Integer(ENV.fetch('PUBLIC_CALCULATOR_CACHE_TTL', DEFAULT_EDGE_TTL), 10)
  rescue ArgumentError
    DEFAULT_EDGE_TTL
  end

  def cache_durations_before_year_boundary(fresh_ttl)
    return [fresh_ttl, STALE_TTL] unless controller_name == 'days' && params[:year].blank?

    now = Time.zone.now
    year_boundary = Time.zone.local(now.year + 1, 1, 1)
    seconds_remaining = [(year_boundary - now).floor, 0].max
    bounded_fresh_ttl = [fresh_ttl, seconds_remaining].min
    bounded_stale_ttl = [STALE_TTL, seconds_remaining - bounded_fresh_ttl].min

    [bounded_fresh_ttl, bounded_stale_ttl]
  end
end
