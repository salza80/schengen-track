require 'test_helper'

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
      end

      test 'rate limits calculation requests by ip' do
        with_calculation_rate_limit(2) do
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

        assert_response :too_many_requests

        error = JSON.parse(response.body).dig('errors', 0)
        assert_equal 'rate_limited', error['code']
        assert_equal 2, error['limit']
        assert_equal Api::V1::CalculationsController::RATE_LIMIT_PERIOD.to_i, error['period_seconds']
        assert_equal '0', response.headers['RateLimit-Remaining']
        assert_equal '2', response.headers['RateLimit-Limit']
      end

      test 'documents the API for agents' do
        get api_docs_path

        assert_response :success

        body = JSON.parse(response.body)
        assert_equal 'Schengen Calculator API', body['name']
        assert_equal 'POST', body.dig('endpoints', 0, 'method')
      end

      test 'serves openapi json through rails routing' do
        get '/openapi.json'

        assert_response :success
        assert_equal 'application/json', response.media_type
        assert_equal '3.1.0', JSON.parse(response.body)['openapi']
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
