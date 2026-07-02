require 'test_helper'

module AgentCalculations
  class CreateTest < ActiveSupport::TestCase
    test 'returns a stable error code for unexpected record validation failures' do
      invalid_user = User.new
      invalid_user.errors.add(:email, "can't be blank")

      User.stub(:create!, ->(**_attributes) { raise ActiveRecord::RecordInvalid.new(invalid_user) }) do
        result = Create.new(
          params: calculation_params,
          url_helpers: Rails.application.routes.url_helpers,
          base_url: 'http://www.example.com'
        ).call

        refute result.success?

        error = result.errors.first
        assert_equal 'record_invalid', error[:code]
        assert_equal 'user', error[:field]
        assert_match(/Email can't be blank/, error[:message])
      end
    end

    test 'rejects trips that are not an array of objects' do
      assert_no_difference('User.count') do
        result = Create.new(
          params: calculation_params.merge(
            'trips' => {
              'country_code' => 'DE',
              'entry_date' => '2026-07-01',
              'exit_date' => '2026-07-20'
            }
          ),
          url_helpers: Rails.application.routes.url_helpers,
          base_url: 'http://www.example.com'
        ).call

        refute result.success?

        error = result.errors.first
        assert_equal 'invalid_trips', error[:code]
        assert_equal 'trips', error[:field]
        assert_match(/array of objects/, error[:message])
      end
    end

    test 'rejects trip entries that are not objects' do
      assert_no_difference('User.count') do
        result = Create.new(
          params: calculation_params.merge('trips' => ['DE']),
          url_helpers: Rails.application.routes.url_helpers,
          base_url: 'http://www.example.com'
        ).call

        refute result.success?

        error = result.errors.first
        assert_equal 'invalid_trips', error[:code]
        assert_equal 'trips[0]', error[:field]
        assert_match(/must be an object/, error[:message])
      end
    end

    test 'rejects visas that are not an array of objects' do
      assert_no_difference('User.count') do
        result = Create.new(
          params: calculation_params.merge(
            'visas' => {
              'visa_type' => 'S',
              'start_date' => '2026-01-01',
              'end_date' => '2026-12-31',
              'no_entries' => 0
            }
          ),
          url_helpers: Rails.application.routes.url_helpers,
          base_url: 'http://www.example.com'
        ).call

        refute result.success?

        error = result.errors.first
        assert_equal 'invalid_visas', error[:code]
        assert_equal 'visas', error[:field]
        assert_match(/array of objects/, error[:message])
      end
    end

    private

    def calculation_params
      {
        'user' => {
          'first_name' => 'Sam',
          'last_name' => 'Traveler',
          'nationality' => 'US'
        },
        'trips' => [
          {
            'country_code' => 'DE',
            'entry_date' => '2026-07-01',
            'exit_date' => '2026-07-20'
          }
        ]
      }
    end
  end
end
