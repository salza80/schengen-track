require 'test_helper'
require 'minitest/mock'
require 'securerandom'

module Api
  module V1
    class CalculationsControllerTest < ActionDispatch::IntegrationTest
      test 'creates a guest calculation and returns structured results with a web URL' do
        assert_difference('User.count', 1) do
          assert_difference('Visit.count', 1) do
            post api_v1_calculations_path,
                 params: calculation_payload,
                 as: :json
          end
        end

        assert_response :created

        body = JSON.parse(response.body)
        assert_equal 'safe', body['status']
        assert_equal 20, body['days_used']
        assert_equal 70, body['days_remaining']
        assert_equal false, body['overstay']
        assert_match %r{\Ahttp://www.example.com/en/days\?guest_calculation=}, body['web_url']
        refute_includes body['web_url'], 'year='
        refute_includes body['web_url'], 'month='
        refute_includes body['web_url'], 'day='
        assert_includes body['web_url'], 'guest_calculation='
        assert_equal body['web_url'], body['claim_url']
        assert_includes body['user_message'], body['web_url']
        assert_includes body['user_message'], 'view, review, edit, or save'
        assert_equal 'US', body.dig('person', 'nationality')
        assert_equal 'DE', body.dig('trips', 0, 'country_code')

        user = User.order(:created_at).last
        guest_token = Rack::Utils.parse_query(URI.parse(body['web_url']).query).fetch('guest_calculation')
        assert_equal guest_token, body['calculation_id']
        refute_equal "guest_#{user.id}", body['calculation_id']
        assert user.is_guest?
        assert_match(/\Aagent_guest_/, user.email)
      end

      test 'tracks successful agent api calculation event' do
        tracked = []

        with_analytics_tracking_stub(tracked) do
          post api_v1_calculations_path,
               params: calculation_payload,
               as: :json
        end

        assert_response :created
        assert_equal 'agent_api_calculation_created', tracked.dig(0, 0)
        assert_equal 'safe', tracked.dig(0, 1, :status)
        assert_equal 1, tracked.dig(0, 1, :trip_count)
        assert_equal 'api', tracked.dig(0, 1, :source)
      end

      test 'tracks mcp source when calculation came from mcp lambda' do
        tracked = []

        with_agent_auth_secret('agent-secret') do
          with_analytics_tracking_stub(tracked) do
            post api_v1_calculations_path,
                 params: calculation_payload,
                 headers: mcp_headers(secret: 'agent-secret'),
                 as: :json
          end
        end

        assert_response :created
        assert_equal 'agent_api_calculation_created', tracked.dig(0, 0)
        assert_equal 'mcp', tracked.dig(0, 1, :source)
      end

      test 'does not trust cloudfront origin auth as mcp agent auth' do
        tracked = []

        with_temporary_env('SCHENGEN_AGENT_AUTH_HEADER', nil) do
          with_temporary_env('CLOUDFRONT_ORIGIN_AUTH_HEADER', 'origin-secret') do
            with_analytics_tracking_stub(tracked) do
              post api_v1_calculations_path,
                   params: calculation_payload,
                   headers: mcp_headers(secret: 'origin-secret'),
                   as: :json
            end
          end
        end

        assert_response :created
        assert_equal 'agent_api_calculation_created', tracked.dig(0, 0)
        assert_equal 'api', tracked.dig(0, 1, :source)
      end

      test 'does not trust spoofed mcp source header without agent auth' do
        tracked = []

        with_agent_auth_secret('agent-secret') do
          with_analytics_tracking_stub(tracked) do
            post api_v1_calculations_path,
                 params: calculation_payload,
                 headers: {
                   'X-Schengen-Agent-Source' => 'mcp',
                   'X-Schengen-Agent-Client-Id' => 'spoofed-client'
                 },
                 as: :json
          end
        end

        assert_response :created
        assert_equal 'agent_api_calculation_created', tracked.dig(0, 0)
        assert_equal 'api', tracked.dig(0, 1, :source)
      end

      test 'does not compare mismatched agent auth lengths' do
        tracked = []

        with_agent_auth_secret('agent-secret') do
          ActiveSupport::SecurityUtils.stub(:secure_compare, ->(_provided, _expected) { raise 'secure_compare should not be called' }) do
            with_analytics_tracking_stub(tracked) do
              post api_v1_calculations_path,
                   params: calculation_payload,
                   headers: mcp_headers(secret: 'short'),
                   as: :json
            end
          end
        end

        assert_response :created
        assert_equal 'agent_api_calculation_created', tracked.dig(0, 0)
        assert_equal 'api', tracked.dig(0, 1, :source)
      end

      test 'tracks rejected agent api calculation event' do
        tracked = []

        with_analytics_tracking_stub(tracked) do
          post api_v1_calculations_path,
               params: calculation_payload.deep_merge(trips: [{ country_code: 'XX' }]),
               as: :json
        end

        assert_response :unprocessable_entity
        assert_equal 'agent_api_calculation_rejected', tracked.dig(0, 0)
        assert_equal 1, tracked.dig(0, 1, :error_count)
        assert_equal 'api', tracked.dig(0, 1, :source)
      end

      test 'returned web URL restores the guest calculation in the website' do
        post api_v1_calculations_path,
             params: calculation_payload,
             as: :json

        body = JSON.parse(response.body)
        uri = URI.parse(body['web_url'])

        get uri.request_uri

        assert_response :redirect
        assert_equal User.order(:created_at).last.id, session[:guest_user_id]
        refute_includes response.location, 'guest_calculation='
        assert_includes response.location, 'year=2026'
        assert_includes response.location, 'month=7'
        assert_includes response.location, 'day=1'

        follow_redirect!

        assert_response :success
        assert_equal User.order(:created_at).last.id, session[:guest_user_id]
      end

      test 'guest calculation link without date params redirects to first entry date' do
        post api_v1_calculations_path,
             params: calculation_payload,
             as: :json

        uri = URI.parse(JSON.parse(response.body)['web_url'])
        guest_token = Rack::Utils.parse_query(uri.query).fetch('guest_calculation')

        get days_path(locale: I18n.default_locale, guest_calculation: guest_token)

        assert_response :redirect
        refute_includes response.location, 'guest_calculation='
        assert_includes response.location, 'year=2026'
        assert_includes response.location, 'month=7'
        assert_includes response.location, 'day=1'

        follow_redirect!

        assert_response :success
        assert_select '#calendar-scroll-target[data-month="7"][data-day="1"]', 1
        assert_select '.calendar-year-nav', /2026/
      end

      test 'short calculation link redirects to first entry date' do
        post api_v1_calculations_path,
             params: calculation_payload,
             as: :json

        user = User.order(:created_at).last
        token = user.signed_id(purpose: :agent_calculation)

        get calculation_link_path(token)

        assert_response :redirect
        assert_equal user.id, session[:guest_user_id]
        assert_includes response.location, 'year=2026'
        assert_includes response.location, 'month=7'
        assert_includes response.location, 'day=1'
      end

      test 'short calculation link rejects non-guest tokens' do
        user = users(:Sally)
        token = user.signed_id(purpose: :agent_calculation)

        get calculation_link_path(token)

        assert_redirected_to root_path(locale: I18n.default_locale)
        assert_equal 'Calculation link is invalid or has expired.', flash[:alert]
        refute_equal user.id, session[:guest_user_id]
        refute_equal user.people.first.id, session[:current_person_id]
      end

      test 'guest calculation param does not restore session on non-get requests' do
        get days_path(locale: I18n.default_locale)

        current_guest_id = session[:guest_user_id]
        current_person = User.find(current_guest_id).people.first
        agent_guest = User.create!(
          guest: true,
          email: "agent_guest_#{SecureRandom.hex(8)}@example.com",
          password: Devise.friendly_token[0, 20],
          first_name: 'Agent',
          last_name: 'Guest',
          nationality: countries(:USA)
        )
        token = agent_guest.signed_id(purpose: :agent_calculation)

        post set_current_person_path(
          current_person,
          locale: I18n.default_locale,
          guest_calculation: token
        )

        assert_response :redirect
        assert_equal current_guest_id, session[:guest_user_id]
        assert_equal current_person.id, session[:current_person_id]
      end

      test 'invalid guest calculation param falls back to a normal guest account' do
        get days_path(locale: I18n.default_locale, guest_calculation: 'invalid-token')

        assert_response :success
        assert User.find(session[:guest_user_id]).is_guest?
      end

      test 'creates a public guest calculation without accepting user email or bearer token' do
        post api_v1_calculations_path,
             params: calculation_payload.deep_merge(user: { email: 'traveler@example.com' }),
             as: :json

        assert_response :created

        body = JSON.parse(response.body)
        assert_equal 'safe', body['status']
        assert_match %r{\Ahttp://www.example.com/en/days\?guest_calculation=}, body['web_url']
        assert_match(/\Aagent_guest_/, User.order(:created_at).last.email)
      end

      test 'returns machine readable validation errors' do
        assert_no_difference('User.count') do
          post api_v1_calculations_path,
               params: calculation_payload.deep_merge(trips: [{ country_code: 'XX' }]),
               as: :json
        end

        assert_response :unprocessable_entity

        error = JSON.parse(response.body).fetch('errors').first
        assert_equal 'invalid_input', error['code']
        assert_equal 'base', error['field']
        assert_match(/country_code/, error['message'])
      end

      test 'returns structured validation error for missing nationality' do
        assert_no_difference('User.count') do
          post api_v1_calculations_path,
               params: calculation_payload.deep_merge(user: { nationality: nil }),
               as: :json
        end

        assert_response :unprocessable_entity

        error = JSON.parse(response.body).fetch('errors').first
        assert_equal 'missing_nationality', error['code']
        assert_equal 'user.nationality', error['field']
        assert_match(/nationality is required/, error['message'])
      end

      test 'rejects too many trips before creating a guest account' do
        too_many_trips = Array.new(AgentCalculations::Create::MAX_TRIPS + 1) do
          {
            country_code: 'DE',
            entry_date: '2026-07-01',
            exit_date: '2026-07-01'
          }
        end

        assert_no_difference('User.count') do
          post api_v1_calculations_path,
               params: calculation_payload.merge(trips: too_many_trips),
               as: :json
        end

        assert_response :unprocessable_entity

        error = JSON.parse(response.body).dig('errors', 0)
        assert_equal 'too_many_trips', error['code']
        assert_equal AgentCalculations::Create::MAX_TRIPS, error['limit']
        assert_equal AgentCalculations::Create::MAX_TRIPS + 1, error['received']
        assert_match(/Too many trips/, error['message'])
      end

      test 'rejects too many visas before creating a guest account' do
        too_many_visas = Array.new(AgentCalculations::Create::MAX_VISAS + 1) do
          {
            visa_type: 'S',
            start_date: '2026-01-01',
            end_date: '2026-12-31',
            no_entries: 0
          }
        end

        assert_no_difference('User.count') do
          post api_v1_calculations_path,
               params: calculation_payload.merge(visas: too_many_visas),
               as: :json
        end

        assert_response :unprocessable_entity

        error = JSON.parse(response.body).dig('errors', 0)
        assert_equal 'too_many_visas', error['code']
        assert_equal AgentCalculations::Create::MAX_VISAS, error['limit']
        assert_equal AgentCalculations::Create::MAX_VISAS + 1, error['received']
        assert_match(/Too many visas/, error['message'])
      end

      test 'rejects oversized request bodies' do
        post api_v1_calculations_path,
             params: { padding: 'x' * (Api::V1::CalculationsController::MAX_REQUEST_BYTES + 1) }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }

        assert_response :payload_too_large

        error = JSON.parse(response.body).dig('errors', 0)
        assert_equal 'payload_too_large', error['code']
        assert_equal Api::V1::CalculationsController::MAX_REQUEST_BYTES, error['limit']
        assert_operator error['received'], :>, Api::V1::CalculationsController::MAX_REQUEST_BYTES
        assert_match(/Request body is too large/, error['message'])
      end

      test 'rejects oversized malformed json without parsing request params' do
        tracked = []
        body = '{"padding":"' + ('x' * (Api::V1::CalculationsController::MAX_REQUEST_BYTES + 1))

        with_analytics_tracking_stub(tracked) do
          post api_v1_calculations_path,
               params: body,
               headers: { 'CONTENT_TYPE' => 'application/json' }
        end

        assert_response :payload_too_large

        error = JSON.parse(response.body).dig('errors', 0)
        assert_equal 'payload_too_large', error['code']
        assert_equal 'agent_api_payload_too_large', tracked.dig(0, 0)
        assert_nil tracked.dig(0, 1, :trip_count)
        assert_equal 'api', tracked.dig(0, 1, :source)
      end

      test 'rate limits calculation requests by ip' do
        tracked = []

        with_calculation_rate_limit(2) do
          with_analytics_tracking_stub(tracked) do
            2.times do
              post api_v1_calculations_path,
                   params: calculation_payload,
                   as: :json

              assert_response :created
            end

            assert_no_difference('User.count') do
              post api_v1_calculations_path,
                   params: calculation_payload,
                   as: :json
            end
          end
        end

        assert_response :too_many_requests

        error = JSON.parse(response.body).dig('errors', 0)
        assert_equal 'rate_limited', error['code']
        assert_equal 2, error['limit']
        assert_equal Api::V1::CalculationsController::RATE_LIMIT_PERIOD.to_i, error['period_seconds']
        assert_equal '0', response.headers['RateLimit-Remaining']
        assert_equal '2', response.headers['RateLimit-Limit']

        event_name, event_params = tracked.last
        assert_equal 'agent_api_rate_limited', event_name
        assert_equal 'rate_limited', event_params[:first_error_code]
        assert_equal 2, event_params[:limit]
        assert_equal 0, event_params[:remaining]
        assert_equal Api::V1::CalculationsController::RATE_LIMIT_PERIOD.to_i, event_params[:period_seconds]
        assert_equal 1, event_params[:trip_count]
        assert_equal 'api', event_params[:source]
      end

      test 'rate limits trusted mcp requests by original caller id' do
        tracked = []
        client_a = "client-a-#{SecureRandom.hex(4)}"
        client_b = "client-b-#{SecureRandom.hex(4)}"

        with_calculation_rate_limit(1) do
          with_agent_auth_secret('agent-secret') do
            with_analytics_tracking_stub(tracked) do
              post api_v1_calculations_path,
                   params: calculation_payload,
                   headers: mcp_headers(client_id: client_a, secret: 'agent-secret'),
                   as: :json

              assert_response :created

              post api_v1_calculations_path,
                   params: calculation_payload,
                   headers: mcp_headers(client_id: client_b, secret: 'agent-secret'),
                   as: :json

              assert_response :created

              assert_no_difference('User.count') do
                post api_v1_calculations_path,
                     params: calculation_payload,
                     headers: mcp_headers(client_id: client_a, secret: 'agent-secret'),
                     as: :json
              end
            end
          end
        end

        assert_response :too_many_requests

        error = JSON.parse(response.body).dig('errors', 0)
        assert_equal 'rate_limited', error['code']
        assert_equal 1, error['limit']

        event_name, event_params = tracked.last
        assert_equal 'agent_api_rate_limited', event_name
        assert_equal 'mcp', event_params[:source]
      end

      test 'documents the API for agents' do
        get api_docs_path

        assert_response :success

        body = JSON.parse(response.body)
        assert_equal 'Schengen Calculator API', body['name']
        assert_includes body['agent_instruction'], 'show the returned web_url or claim_url to the user'
        assert_equal 'POST', body.dig('endpoints', 0, 'method')
        assert_includes body.dig('endpoints', 0, 'purpose'), 'show the user'
      end

      test 'serves openapi json through rails routing' do
        get '/openapi.json'

        assert_response :success
        assert_equal 'application/json', response.media_type
        schema = JSON.parse(response.body)
        error_properties = schema.dig('components', 'schemas', 'ErrorResponse', 'properties', 'errors', 'items', 'properties')

        assert_equal '3.1.0', schema['openapi']
        assert_equal '/', schema.dig('servers', 0, 'url')
        assert_equal 'integer', error_properties.dig('period_seconds', 'type')
        assert_equal 'date-time', error_properties.dig('reset_at', 'format')
        assert_includes error_properties.dig('code', 'examples'), 'invalid_input'
        assert_includes error_properties.dig('code', 'examples'), 'record_invalid'
      end

      private

      def with_analytics_tracking_stub(tracked)
        original = Analytics::GoogleMeasurementProtocol.method(:track)
        Analytics::GoogleMeasurementProtocol.define_singleton_method(:track) do |event_name, request:, params:|
          tracked << [event_name, params]
        end
        yield
      ensure
        Analytics::GoogleMeasurementProtocol.define_singleton_method(:track, original)
      end

      def with_calculation_rate_limit(limit)
        original_limit = Api::V1::CalculationsController::RATE_LIMIT
        Api::V1::CalculationsController.send(:remove_const, :RATE_LIMIT)
        Api::V1::CalculationsController.const_set(:RATE_LIMIT, limit)
        yield
      ensure
        Api::V1::CalculationsController.send(:remove_const, :RATE_LIMIT)
        Api::V1::CalculationsController.const_set(:RATE_LIMIT, original_limit)
      end

      def with_agent_auth_secret(secret)
        with_temporary_env('SCHENGEN_AGENT_AUTH_HEADER', secret) { yield }
      end

      def with_temporary_env(key, value)
        original_value = ENV[key]
        value.nil? ? ENV.delete(key) : ENV[key] = value
        yield
      ensure
        original_value.nil? ? ENV.delete(key) : ENV[key] = original_value
      end

      def mcp_headers(client_id: 'mcp-test-client', secret: 'agent-secret')
        {
          'X-Schengen-Agent-Source' => 'mcp',
          'X-Schengen-Agent-Auth' => secret,
          'X-Schengen-Agent-Client-Id' => client_id
        }
      end

      def calculation_payload
        {
          user: {
            first_name: 'Sam',
            last_name: 'Traveler',
            nationality: 'US'
          },
          trips: [
            {
              country_code: 'DE',
              entry_date: '2026-07-01',
              exit_date: '2026-07-20'
            }
          ]
        }
      end
    end
  end
end
