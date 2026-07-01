require 'digest'
require 'json'
require 'net/http'

module Analytics
  class GoogleMeasurementProtocol
    ENDPOINT = 'https://www.google-analytics.com/mp/collect'
    TIMEOUT_SECONDS = 2

    def self.track(event_name, request:, params: {})
      new.track(event_name, request: request, params: params)
    end

    def track(event_name, request:, params: {})
      return unless configured?

      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(
        measurement_id: AppConfig.google_analytics_measurement_id,
        api_secret: AppConfig.google_analytics_api_secret
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS

      http.post(
        uri.request_uri,
        JSON.generate(payload_for(event_name, request, params)),
        'Content-Type' => 'application/json'
      )
    rescue StandardError => e
      Rails.logger.info("Google Analytics Measurement Protocol event failed: #{e.class}: #{e.message}")
    end

    private

    def configured?
      AppConfig.google_analytics_measurement_id.present? && AppConfig.google_analytics_api_secret.present?
    end

    def payload_for(event_name, request, params)
      {
        client_id: client_id_for(request),
        events: [
          {
            name: event_name,
            params: default_params(request).merge(params.compact)
          }
        ]
      }
    end

    def default_params(request)
      {
        engagement_time_msec: 1,
        method: request.request_method,
        path: request.path,
        user_agent_present: request.user_agent.present?
      }
    end

    def client_id_for(request)
      Digest::SHA256.hexdigest([
        request.remote_ip,
        request.user_agent,
        request.headers['X-Forwarded-For']
      ].compact.join('|'))[0, 32]
    end
  end
end
