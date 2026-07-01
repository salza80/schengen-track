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
          render json: result.payload, status: :created
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      private

      def reject_large_payload!
        received_bytes = [request.content_length.to_i, request.raw_post.bytesize].max
        return unless received_bytes > MAX_REQUEST_BYTES

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
    end
  end
end
