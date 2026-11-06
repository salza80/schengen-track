require 'test_helper'

class PrivateCalculatorBrowserTest < JavascriptIntegrationTest
  test 'saved trip rows open the private calendar directly' do
    user_login
    find('tr[data-clickable-row="true"]', match: :first).click
    assert_current_path private_days_path(locale: :en), ignore_query: true, wait: 10
    assert_equal '/en/my/days', URI(page.current_url).path
  end

  test 'validated header continuation opens saved data with its calendar presentation' do
    user_login
    visit days_path(locale: :fr, year: 2014, month: 2)
    assert_current_path private_days_path(locale: :fr), ignore_query: true, wait: 10
    assert_equal({ 'year' => '2014', 'month' => '2' }, URI.decode_www_form(URI(page.current_url).query).to_h)
    assert_selector '#personDropdown', text: 'Sally Mclean'
    assert_no_selector 'body[data-public-calculator-page="true"]'
    assert_equal '/fr/my/days', URI(page.current_url).path
  end

  test 'native login navigation and saved-calculator links work without JavaScript' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    page.driver.browser.execute_cdp('Emulation.setScriptExecutionDisabled', value: true)
    user_login
    assert_selector 'a[href="/en/my/days"]'
    find('a[href="/en/my/days"]', match: :first).click
    assert_current_path private_days_path(locale: :en), wait: 10
    assert_selector '#personDropdown', text: 'Sally Mclean'

    visit visits_path(locale: :en)
    assert_selector 'body[data-public-calculator-page="true"]'
    click_link I18n.t('common.my_calculator'), match: :first
    assert_current_path private_visits_path(locale: :en), wait: 10
    assert_selector '#personDropdown', text: 'Sally Mclean'
    assert_equal '/en/my/visits', URI(page.current_url).path
  ensure
    page.driver.browser.execute_cdp('Emulation.setScriptExecutionDisabled', value: false)
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end
end
