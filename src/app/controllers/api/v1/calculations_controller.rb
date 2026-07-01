module Api
  module V1
    class CalculationsController < BaseController
      MAX_REQUEST_BYTES = 32.kilobytes

      before_action :reject_large_payload!

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
        received_bytes = [request.content_length.to_i, request.raw_post.bytesize].max
        return unless received_bytes > MAX_REQUEST_BYTES

        track_api_event(
          'agent_api_payload_too_large',
          limit: MAX_REQUEST_BYTES,
          received: received_bytes
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

      def calculation_params
        params.permit(
          user: [:email, :first_name, :last_name, :nationality],
          trips: [:country_code, :entry_date, :exit_date],
          visas: [:visa_type, :start_date, :end_date, :no_entries]
        )
      end

      def track_api_event(event_name, data = {})
        Analytics::GoogleMeasurementProtocol.track(
          event_name,
          request: request,
          params: analytics_params(data)
        )
      end

      def analytics_params(data)
        errors = Array(data[:errors])
        {
          status: data[:status],
          days_used: data[:days_used],
          days_remaining: data[:days_remaining],
          overstay: data[:overstay],
          trip_count: Array(data[:trips]).length.presence || Array(params[:trips]).length,
          visa_count: Array(params[:visas]).length,
          error_count: errors.length,
          first_error_code: errors.first&.dig(:code) || errors.first&.dig('code'),
          limit: data[:limit],
          received: data[:received]
        }
      end
    end
  end
end
