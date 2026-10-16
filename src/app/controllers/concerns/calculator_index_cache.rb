# frozen_string_literal: true

# Allows only completely cookie-free calculator index requests to use the
# shared CloudFront cache. Any session hint or legacy calculation-claim token
# is treated as private before Rails attempts to resolve it.
module CalculatorIndexCache
  extend ActiveSupport::Concern

  SESSION_INDICATOR_COOKIES = %w[_schengen_track_session has_calculator_session].freeze
  DEFAULT_EDGE_TTL = 15.minutes.to_i
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
    fresh_ttl = Integer(ENV.fetch('PUBLIC_CALCULATOR_CACHE_TTL', DEFAULT_EDGE_TTL), 10)
    "public, max-age=0, s-maxage=#{fresh_ttl}, stale-while-revalidate=#{STALE_TTL}, stale-if-error=#{STALE_TTL}"
  rescue ArgumentError
    "public, max-age=0, s-maxage=#{DEFAULT_EDGE_TTL}, stale-while-revalidate=#{STALE_TTL}, stale-if-error=#{STALE_TTL}"
  end
end
