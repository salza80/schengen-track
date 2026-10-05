require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'OAuth registration uses the guest primary person nationality' do
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
    ensure
      analytics.define_singleton_method(:track, original_track)
    end
  end
end
