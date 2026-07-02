module Api
  class DocsController < ActionController::API
    def show
      render json: {
        name: 'Schengen Calculator API',
        description: 'Programmatic API for creating saved Schengen 90/180-day calculations. Agents should prefer this API or the MCP endpoint over driving the web UI.',
        agent_instruction: 'After creating a calculation, show the returned web_url or claim_url to the user so they can check, review, edit, or save the calculation.',
        openapi_url: "#{request.base_url}/openapi.json",
        mcp_url: "#{request.base_url}/mcp",
        endpoints: [
          {
            method: 'POST',
            path: '/api/v1/calculations',
            auth: 'none',
            purpose: 'Create a guest calculation from traveler details and trips, then return structured results and a website URL to show the user.',
            limits: {
              request_body: '32 KB',
              rate_limit: "#{Api::V1::CalculationsController::RATE_LIMIT} requests per #{Api::V1::CalculationsController::RATE_LIMIT_PERIOD.to_i} seconds per client IP for public API calls, or per original MCP caller for trusted MCP calls",
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
