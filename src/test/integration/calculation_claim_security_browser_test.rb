require 'test_helper'

class CalculationClaimSecurityBrowserTest < JavascriptIntegrationTest
  test 'opening the link loads only local resources and cancel leaves it unused' do
    source = create_source
    token = source.signed_id(purpose: :agent_calculation, expires_in: 30.days)
    visit calculation_link_path(token)

    assert_selector 'input[type="submit"]', visible: :all
    assert_nil source.reload.calculation_claimed_at
    assert_no_selector 'script, iframe, link[rel="preconnect"], link[rel="dns-prefetch"]', visible: :all
    assert_empty page.evaluate_script(<<~JS)
      performance.getEntriesByType('resource')
        .filter(entry => new URL(entry.name).origin !== window.location.origin)
        .map(entry => entry.name)
    JS
    click_link I18n.t('calculation_claim.cancel', locale: :en)
    assert_current_path visits_path(locale: :en)
    assert_equal '', page.evaluate_script('document.referrer')
    assert_not_includes page.current_url, token
    assert_nil source.reload.calculation_claimed_at
  end

  test 'native no-referrer confirmation works with real browser CSRF protection and cannot be replayed' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    source = create_source
    token = source.signed_id(purpose: :agent_calculation, expires_in: 30.days)
    visit calculation_link_path(token)

    assert_difference('User.count', 1) do
      click_button I18n.t('calculation_claim.confirm', locale: :en)
      assert_current_path private_days_path(locale: :en)
    end
    assert source.reload.calculation_claimed_at.present?
    private_guest = User.order(:id).last
    refute_equal source, private_guest
    assert_equal 'Browser Claim', private_guest.people.first.full_name
    visit calculation_link_path(token)
    assert_current_path root_path(locale: :en)
    assert_equal private_guest, User.order(:id).last
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  private

  def create_source
    User.create!(guest: true, email: "browser_claim_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                 first_name: 'Browser', last_name: 'Claim', nationality: countries(:USA))
  end
end
