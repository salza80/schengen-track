module Api
  module V1
    class CalculationsController < BaseController
      MAX_REQUEST_BYTES = 32.kilobytes
      RATE_LIMIT = 30
      RATE_LIMIT_PERIOD = 10.minutes

      before_action :reject_large_payload!
      before_action :rate_limit!

      def create
        result = AgentCalculations::Create.new(
          params: calculation_params.to_h,
          url_helpers: Rails.application.routes.url_helpers,
          base_url: request.base_url
        ).call

        if result.success?
          track_api_event('agent_api_calculation_created', result.payload)
          render json: result.payload, status: :created
        else
          track_api_event('agent_api_calculation_rejected', errors: result.errors)
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      private

      def reject_large_payload!
        received_bytes = request.content_length.to_i
        received_bytes = request.env['rack.input'].size if received_bytes.zero? && request.env['rack.input'].respond_to?(:size)
        return unless received_bytes > MAX_REQUEST_BYTES

        track_api_event(
          'agent_api_payload_too_large',
          limit: MAX_REQUEST_BYTES,
          received: received_bytes,
          include_request_params: false
        )

        render json: {
          errors: [
            {
              code: 'payload_too_large',
              field: 'base',
              message: "Request body is too large. Maximum size is #{MAX_REQUEST_BYTES} bytes.",
              limit: MAX_REQUEST_BYTES,
              received: received_bytes
            }
          ]
        }, status: :payload_too_large
      end

      def rate_limit!
        result = RateLimiters::DatabaseFixedWindow.new(
          scope: 'api:v1:calculations:create',
          identifier: rate_limit_identifier,
          limit: RATE_LIMIT,
          period: RATE_LIMIT_PERIOD
        ).call

        response.set_header('RateLimit-Limit', result.limit.to_s)
        response.set_header('RateLimit-Remaining', result.remaining.to_s)
        response.set_header('RateLimit-Reset', result.reset_at.to_i.to_s)
        return if result.allowed?

        render json: {
          errors: [
            {
              code: 'rate_limited',
              field: 'base',
              message: "Too many calculation requests. Try again after #{result.reset_at.utc.iso8601}.",
              limit: result.limit,
              period_seconds: RATE_LIMIT_PERIOD.to_i,
              reset_at: result.reset_at.utc.iso8601
            }
          ]
        }, status: :too_many_requests
      end

      def calculation_params
        params.permit(
          user: [:email, :first_name, :last_name, :nationality],
          trips: [:country_code, :entry_date, :exit_date],
          visas: [:visa_type, :start_date, :end_date, :no_entries]
        )
      end

      def rate_limit_identifier
        request.get_header('schengen.client_ip').presence || request.remote_ip
      end

      def track_api_event(event_name, data = {})
        include_request_params = data.delete(:include_request_params) { true }
        Analytics::GoogleMeasurementProtocol.track(
          event_name,
          request: request,
          params: analytics_params(data, include_request_params: include_request_params)
        )
      end

      def analytics_params(data, include_request_params: true)
        errors = Array(data[:errors])
        trip_count = Array(data[:trips]).length if data.key?(:trips)
        visa_count = Array(data[:visas]).length if data.key?(:visas)

        if include_request_params
          trip_count ||= Array(params[:trips]).length
          visa_count ||= Array(params[:visas]).length
        end

        {
          status: data[:status],
          days_used: data[:days_used],
          days_remaining: data[:days_remaining],
          overstay: data[:overstay],
          trip_count: trip_count,
          visa_count: visa_count,
          error_count: errors.length,
          first_error_code: errors.first&.dig(:code) || errors.first&.dig('code'),
          limit: data[:limit],
          received: data[:received]
        }
      end
    end
  end
end
