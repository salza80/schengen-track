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

  test 'Facebook email collision cannot claim a pre-registered local account' do
    account = users(:Sally)
    original_attributes = account.attributes
    guest = users(:VisaRequiredUser)
    auth = facebook_auth(email: account.email)
    auth.credentials = { token: 'private-provider-token' }

    stdout, stderr = capture_io do
      capture_analytics_events do |events|
        assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
          result = User.from_omniauth(auth, guest)
          assert_not result.persisted?
          assert result.errors.of_kind?(:email, :taken)
        end
        assert_empty events
      end
    end

    assert_equal original_attributes, account.reload.attributes
    assert_empty stdout
    assert_empty stderr
  end

  test 'Facebook email collision is rejected regardless of email case' do
    account = users(:Sally)
    result = User.from_omniauth(facebook_auth(email: account.email.upcase), nil)

    assert_not result.persisted?
    assert result.errors.of_kind?(:email, :taken)
    assert_nil account.reload.provider
    assert_nil account.uid
  end

  test 'a different Facebook identity cannot replace an existing link with the same email' do
    account = users(:Sally)
    account.update!(provider: 'facebook', uid: 'original-facebook-user')

    result = User.from_omniauth(facebook_auth(email: account.email), nil)

    assert_not result.persisted?
    assert result.errors.of_kind?(:email, :taken)
    assert_equal 'original-facebook-user', account.reload.uid
  end

  test 'an existing Facebook identity signs in by provider and uid even if the provider email changes' do
    account = users(:Sally)
    account.update!(provider: 'facebook', uid: 'existing-facebook-user')
    original_email = account.email

    assert_no_difference(['User.count', 'Person.count']) do
      result = User.from_omniauth(facebook_auth(email: 'changed@example.com', uid: account.uid), nil)
      assert_equal account, result
    end
    assert_equal original_email, account.reload.email
  end

  test 'missing Facebook email returns validation errors without copying data or tracking signup' do
    capture_analytics_events do |events|
      assert_no_difference(['User.count', 'Person.count']) do
        result = User.from_omniauth(facebook_auth(email: nil), users(:VisaRequiredUser))
        assert_not result.persisted?
        assert result.errors.of_kind?(:email, :blank)
      end
      assert_empty events
    end
  end

  test 'an incomplete or unsupported OAuth identity cannot match an unlinked account' do
    [nil, '', 'other-provider'].each do |provider|
      result = User.from_omniauth(facebook_auth(provider: provider, uid: nil), nil)
      assert_not result.persisted?
      assert result.errors.of_kind?(:base, :invalid)
    end

    result = User.from_omniauth(facebook_auth(uid: ''), nil)
    assert_not result.persisted?
    assert result.errors.of_kind?(:base, :invalid)
  end

  private

  def facebook_auth(email: 'new-facebook-user@example.com', uid: 'new-facebook-user', provider: 'facebook')
    OmniAuth::AuthHash.new(
      provider: provider, uid: uid,
      info: { email: email, first_name: 'Facebook', last_name: 'User' },
      extra: { raw_info: nil }
    )
  end
end
