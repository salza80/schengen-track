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
