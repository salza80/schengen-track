# frozen_string_literal: true

module GuestCalculatorAbuseControl
  extend ActiveSupport::Concern
  WRITE_LIMIT = 30
  WRITE_PERIOD = 10.minutes

  included do
    before_action :limit_guest_allocations!, only: :create
    rescue_from GuestCalculations::Capacity::Exceeded, with: :guest_capacity_exceeded
    rescue_from RateLimiters::DatabaseFixedWindow::Unavailable, with: :guest_limiter_unavailable
  end

  private

  def limit_guest_allocations!
    user = current_user_or_guest_user
    return if user && !user.is_guest?

    # Lambda sets this Rack value from the gateway/verified edge identity.
    # Never read the viewer-supplied X-Schengen-Client-Ip header here.
    ip = request.get_header('schengen.client_ip').presence || request.remote_ip
    identifiers = [['guest:web:allocations:ip', ip]]
    identifiers << ['guest:web:allocations:account', user.id.to_s] if user
    identifiers.each do |scope, identifier|
      result = RateLimiters::DatabaseFixedWindow.new(
        scope: scope, identifier: identifier, limit: WRITE_LIMIT, period: WRITE_PERIOD
      ).call
      next if result.allowed?

      response.set_header('Retry-After', [(result.reset_at - Time.current).ceil, 1].max.to_s)
      return guest_allocation_error('rate_limited', t('common.calculator_rate_limited'), :too_many_requests)
    end
  end

  def guest_capacity_exceeded
    guest_allocation_error('calculator_capacity_reached', t('common.calculator_capacity_reached'), :too_many_requests)
  end

  def guest_limiter_unavailable
    response.set_header('Retry-After', '60')
    guest_allocation_error('service_unavailable', t('common.calculator_service_unavailable'), :service_unavailable)
  end

  def guest_allocation_error(code, message, status)
    response.set_header('Cache-Control', 'private, no-store')
    respond_to do |format|
      format.html { render plain: message, status: status }
      format.any { render json: { error: { code: code, message: message } }, status: status }
    end
  end
end
