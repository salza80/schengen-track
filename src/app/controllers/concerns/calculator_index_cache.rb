# frozen_string_literal: true

# Allows only completely cookie-free calculator index requests to use the
# shared CloudFront cache. Any session hint or legacy calculation-claim token
# is treated as private before Rails attempts to resolve it.
module CalculatorIndexCache
  extend ActiveSupport::Concern

  SESSION_INDICATOR_COOKIES = %w[_schengen_track_session has_calculator_session].freeze
  DEFAULT_EDGE_TTL = 30.days.to_i
  STALE_TTL = 7.days.to_i

  included do
    prepend_before_action :prepare_calculator_index_cache, only: :index
  end

  private

  def prepare_calculator_index_cache
    if params[:guest_calculation].present? || SESSION_INDICATOR_COOKIES.any? { |name| request.cookies.key?(name) }
      set_private_calculator_cache
      return
    end

    @public_static_page = true
    @public_calculator_page = true
    request.session_options[:skip] = true
    response.headers['Cache-Control'] = public_calculator_cache_control
    response.headers['Vary'] = 'Cookie'
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
