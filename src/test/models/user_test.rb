require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'OAuth registration uses the guest primary nationality and copies every traveler' do
    guest = User.create!(
      first_name: 'Guest',
      last_name: 'User',
      nationality: countries(:USA),
      email: "oauth-guest-#{SecureRandom.hex(8)}@example.com",
      password: 'password',
      guest: true
    )
    guest.people.find_by!(is_primary: true).update!(
      first_name: 'Anna',
      last_name: 'Traveller',
      nationality: countries(:Australia)
    )
    companion = guest.people.create!(
      first_name: 'OAuth',
      last_name: 'Companion',
      nationality: countries(:India)
    )
    companion.visits.create!(
      entry_date: Date.new(2027, 3, 1),
      exit_date: Date.new(2027, 3, 5),
      country: countries(:Germany)
    )
    auth = OmniAuth::AuthHash.new(
      provider: 'facebook',
      uid: SecureRandom.hex(8),
      info: {
        email: "oauth-user-#{SecureRandom.hex(8)}@example.com",
        first_name: nil,
        last_name: nil
      },
      extra: { raw_info: nil }
    )

    analytics = Analytics::GoogleMeasurementProtocol
    original_track = analytics.method(:track)
    analytics.define_singleton_method(:track) { |*args, **kwargs| true }

    begin
      user = User.from_omniauth(auth, guest, countries(:India))

      assert_equal countries(:Australia), user.nationality
      assert_equal countries(:Australia), user.people.find_by!(is_primary: true).nationality
      copied_companion = user.people.find_by!(first_name: 'OAuth', last_name: 'Companion')
      assert_equal countries(:India), copied_companion.nationality
      assert_equal 1, copied_companion.visits.count
      assert_equal countries(:Germany), copied_companion.visits.first.country
    ensure
      analytics.define_singleton_method(:track, original_track)
    end
  end
end
