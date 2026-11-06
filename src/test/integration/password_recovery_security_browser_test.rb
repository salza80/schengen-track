require 'test_helper'

class PasswordRecoverySecurityBrowserTest < JavascriptIntegrationTest
  test 'recovery loads no third-party resources and navigation sends no referrer' do
    token = reset_token_for(users(:Sally))
    visit edit_user_password_path(locale: :en, reset_password_token: token)

    assert_selector '#user_password'
    assert_no_selector 'script, iframe, link[rel="preconnect"], link[rel="dns-prefetch"]', visible: :all
    external_resources = page.evaluate_script(<<~JS)
      performance.getEntriesByType('resource')
        .filter(entry => new URL(entry.name).origin !== window.location.origin)
        .map(entry => entry.name)
    JS
    assert_empty external_resources

    click_link I18n.t('common.schengen_calculator', locale: :en)
    assert_current_path root_path(locale: :en)
    assert_equal '', page.evaluate_script('document.referrer')
    assert_not_includes page.current_url, token
  end

  test 'recovery works without JavaScript using the native form and CSRF protection' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    user = users(:Sally)
    visit edit_user_password_path(locale: :en, reset_password_token: reset_token_for(user))

    assert_selector 'form input[name="authenticity_token"]', visible: :all
    fill_in 'user_password', with: 'browser-recovery-password'
    fill_in 'user_password_confirmation', with: 'browser-recovery-password'
    click_button I18n.t('devise.passwords.edit.change_my_password', locale: :en)

    assert_no_selector '#user_reset_password_token', visible: :all
    assert user.reload.valid_password?('browser-recovery-password')
    assert_nil user.reset_password_token
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  private

  def reset_token_for(user)
    raw, digest = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(reset_password_token: digest, reset_password_sent_at: Time.current)
    raw
  end
end
