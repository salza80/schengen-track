module Api
  module V1
    class CalculationsController < BaseController
      MAX_REQUEST_BYTES = 32.kilobytes
      RATE_LIMIT = 30
      RATE_LIMIT_PERIOD = 10.minutes
      AGENT_SOURCE_HEADER = 'HTTP_X_SCHENGEN_AGENT_SOURCE'
      AGENT_AUTH_HEADER = 'HTTP_X_SCHENGEN_AGENT_AUTH'
      AGENT_CLIENT_ID_HEADER = 'HTTP_X_SCHENGEN_AGENT_CLIENT_ID'
      DEFAULT_AGENT_SOURCE = 'api'
      MCP_AGENT_SOURCE = 'mcp'
      EVENT_CALCULATION_CREATED = 'agent_api_calculation_created'
      EVENT_CALCULATION_REJECTED = 'agent_api_calculation_rejected'
      EVENT_PAYLOAD_TOO_LARGE = 'agent_api_payload_too_large'
      EVENT_RATE_LIMITED = 'agent_api_rate_limited'

      before_action :reject_large_payload!
      before_action :rate_limit!

      def create
        result = AgentCalculations::Create.new(
          params: calculation_params.to_h,
          url_helpers: Rails.application.routes.url_helpers,
          base_url: request.base_url
        ).call

        if result.success?
          track_api_event(EVENT_CALCULATION_CREATED, result.payload)
          render json: result.payload, status: :created
        else
          track_api_event(EVENT_CALCULATION_REJECTED, errors: result.errors)
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      private

      def reject_large_payload!
        received_bytes = request.content_length.to_i
        received_bytes = request.env['rack.input'].size if received_bytes.zero? && request.env['rack.input'].respond_to?(:size)
        return unless received_bytes > MAX_REQUEST_BYTES

        error = {
          code: 'payload_too_large',
          field: 'base',
          message: "Request body is too large. Maximum size is #{MAX_REQUEST_BYTES} bytes.",
          limit: MAX_REQUEST_BYTES,
          received: received_bytes
        }

        track_api_event(
          EVENT_PAYLOAD_TOO_LARGE,
          errors: [error],
          limit: MAX_REQUEST_BYTES,
          received: received_bytes,
          include_request_params: false
        )

        render json: {
          errors: [error]
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

        track_api_event(
          EVENT_RATE_LIMITED,
          errors: [{ code: 'rate_limited' }],
          limit: result.limit,
          remaining: result.remaining,
          period_seconds: RATE_LIMIT_PERIOD.to_i,
          reset_at: result.reset_at.utc.iso8601
        )

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
          user: [:first_name, :last_name, :nationality],
          trips: [:country_code, :entry_date, :exit_date],
          visas: [:visa_type, :start_date, :end_date, :no_entries]
        )
      end

      def rate_limit_identifier
        if trusted_agent_source? && agent_client_id.present?
          return "#{MCP_AGENT_SOURCE}:#{agent_client_id}"
        end

        request.get_header('schengen.client_ip').presence || request.remote_ip
      end

      def agent_source
        trusted_agent_source? ? MCP_AGENT_SOURCE : DEFAULT_AGENT_SOURCE
      end

      def trusted_agent_source?
        return false unless request.get_header(AGENT_SOURCE_HEADER).to_s.downcase == MCP_AGENT_SOURCE

        expected = AppConfig.schengen_agent_auth_header.to_s
        provided = request.get_header(AGENT_AUTH_HEADER).to_s
        return false if expected.blank? || provided.blank?
        return false unless provided.bytesize == expected.bytesize

        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def agent_client_id
        request.get_header(AGENT_CLIENT_ID_HEADER).to_s.presence
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
        trip_count = collection_count(data[:trips]) if data.key?(:trips)
        visa_count = collection_count(data[:visas]) if data.key?(:visas)

        if include_request_params
          trip_count ||= collection_count(params[:trips])
          visa_count ||= collection_count(params[:visas])
        end

        {
          status: data[:status],
          days_used: data[:days_used],
          days_remaining: data[:days_remaining],
          overstay: data[:overstay],
          trip_count: trip_count,
          visa_count: visa_count,
          source: agent_source,
          error_count: errors.length,
          first_error_code: errors.first&.dig(:code) || errors.first&.dig('code'),
          limit: data[:limit],
          remaining: data[:remaining],
          period_seconds: data[:period_seconds],
          reset_at: data[:reset_at],
          received: data[:received]
        }
      end

      def collection_count(value)
        value.length if value.is_a?(Array)
      end
    end
  end
end
