# frozen_string_literal: true

module GuestCalculatorAbuseControl
  extend ActiveSupport::Concern
  WRITE_LIMIT = 30
  WRITE_PERIOD = 10.minutes
  READ_LIMIT = 60
  READ_PERIOD = 1.minute

  included do
    before_action :limit_guest_allocations!, only: :create
    rescue_from GuestCalculations::Capacity::Exceeded, with: :guest_capacity_exceeded
    rescue_from RateLimiters::DatabaseFixedWindow::Unavailable, with: :guest_limiter_unavailable
  end

  private

  def limit_guest_allocations!
    user = current_user_or_guest_user
    return if user && !user.is_guest?

    enforce_guest_quota(user, 'allocations', WRITE_LIMIT, WRITE_PERIOD)
  end

  def limit_guest_reads!
    user = current_user_or_guest_user
    return unless user&.is_guest?

    enforce_guest_quota(user, 'reads', READ_LIMIT, READ_PERIOD)
    return if performed? || !current_person.persisted?

    maximum = GuestCalculations::Capacity::MAX_RECORDS
    records = current_person.visits.limit(maximum + 1).count + current_person.visas.limit(maximum + 1).count
    return unless records > maximum

    if action_name == 'index' && request.format.html?
      @limited_visits = capacity_page(current_person.visits, params[:before_visit]).includes(:country)
      @limited_visas = capacity_page(current_person.visas, params[:before_visa])
      response.set_header('Cache-Control', 'private, no-store')
      render 'shared/calculator_capacity', status: :too_many_requests
    else
      guest_capacity_exceeded
    end
  end

  def capacity_page(records, cursor)
    before_id = Integer(cursor.to_s, exception: false)
    records = records.where('id < ?', before_id) if before_id && before_id.between?(1, 2**63 - 1)
    records.reorder(id: :desc).limit(100)
  end

  def enforce_guest_quota(user, operation, limit, period)

    # Lambda sets this Rack value from the gateway/verified edge identity.
    # Never read the viewer-supplied X-Schengen-Client-Ip header here.
    ip = request.get_header('schengen.client_ip').presence || request.remote_ip
    identifiers = [["guest:web:#{operation}:ip", ip]]
    identifiers << ["guest:web:#{operation}:account", user.id.to_s] if user
    identifiers.each do |scope, identifier|
      result = RateLimiters::DatabaseFixedWindow.new(
        scope: scope, identifier: identifier, limit: limit, period: period
      ).call
      next if result.allowed?

      response.set_header('Retry-After', [(result.reset_at - Time.current).ceil, 1].max.to_s)
      return guest_allocation_error('rate_limited', t('common.calculator_rate_limited'), :too_many_requests)
    end
  end

  def guest_capacity_exceeded
    I18n.with_locale(route_locale || I18n.default_locale) do
      guest_allocation_error('calculator_capacity_reached', t('common.calculator_capacity_reached'), :too_many_requests)
    end
  end

  def guest_limiter_unavailable
    response.set_header('Retry-After', '60')
    I18n.with_locale(route_locale || I18n.default_locale) do
      guest_allocation_error('service_unavailable', t('common.calculator_service_unavailable'), :service_unavailable)
    end
  end

  def guest_allocation_error(code, message, status)
    response.set_header('Cache-Control', 'private, no-store')
    respond_to do |format|
      format.html { render plain: message, status: status }
      format.any { render json: { error: { code: code, message: message } }, status: status }
    end
  end
end
