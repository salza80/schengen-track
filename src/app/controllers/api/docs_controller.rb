module Api
  class DocsController < ActionController::API
    def show
      render json: {
        name: 'Schengen Calculator API',
        description: 'Programmatic API for creating saved Schengen 90/180-day calculations. Agents should prefer this API over driving the web UI.',
        openapi_url: "#{request.base_url}/openapi.json",
        endpoints: [
          {
            method: 'POST',
            path: '/api/v1/calculations',
            auth: 'none',
            purpose: 'Create a guest calculation from traveler details and trips, then return structured results and a website URL.',
            limits: {
              request_body: '32 KB',
              trips: AgentCalculations::Create::MAX_TRIPS,
              visas: AgentCalculations::Create::MAX_VISAS
            }
          }
        ]
      }
    end

    def openapi
      send_file Rails.root.join('public', 'openapi.json'), type: 'application/json', disposition: 'inline'
    end
  end
end
