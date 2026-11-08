require 'test_helper'

class PopupInformationBrowserTest < JavascriptIntegrationTest
  [390, 1400].each do |width|
    test "shared border limits and visit attribution are clear at #{width}px" do
      person = people(:sally_person)
      person.visits.delete_all
      [['2027-01-01', '2027-01-10', :Germany], ['2027-01-10', '2027-01-20', :Australia],
       ['2027-01-20', '2027-01-21', :Germany]].each do |entry, exit_date, country|
        person.visits.create!(country: countries(country), entry_date: entry, exit_date: exit_date)
      end
      page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 844,
                                      deviceScaleFactor: 1, mobile: width == 390)
      user_login
      visit '/en/my/visits'
      assert_selector '.trips-table .shared-entry-note', text: I18n.t('visits.shared_entry_note'), count: 1
      find('.trips-table tbody tr', text: '01 Jan 2027').find('.edit-visit-link').click
      assert_selector '#max-stay-info', text: '10 days until January 10, 2027'
      find('#max-stay-info .exit-date-link').click
      assert_equal '2027-01-10', find('#visit_exit_date').value
      assert_selector '[data-departure-info]', text: 'Days used: 10/90'
      click_button 'Save'
      assert_no_selector '#visitModal.show'
      assert_selector '.trips-table tbody tr', text: '10 Jan 2027'
    ensure
      page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    end

    test "a saved final visit keeps its allowance and previews departure usage at #{width}px" do
      person = people(:sally_person)
      person.visits.delete_all
      [['2027-01-01', '2027-01-30'], ['2027-02-10', '2027-03-11']].each do |entry, exit|
        person.visits.create!(country: countries(:Germany), entry_date: entry, exit_date: exit)
      end
      page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 844,
                                      deviceScaleFactor: 1, mobile: width == 390)
      user_login
      visit '/en/my/days?year=2027&month=4&day=1'
      find('[data-date="2027-04-01"]').click
      assert_selector 'form[data-visit-form-initialized="true"]'
      fill_in 'visit_exit_date', with: Date.new(2027, 4, 30)
      choose_visit_country('Germany')
      assert_selector '#max-stay-info', text: '30 days until April 30, 2027'
      assert_selector '[data-departure-info]', text: 'Days used: 90/90'
      assert_selector '[data-departure-remaining]', text: 'Days remaining after this visit: 0'
      click_button 'Save'
      assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
      assert_selector '[data-date="2027-04-30"] .day-count', text: '90'

      find('[data-date="2027-04-30"]').click
      assert_selector '#entry-date-info [data-entry-days-used]', text: 'Days used: 61/90'
      assert_selector '#max-stay-info', text: '30 days until April 30, 2027'
      fill_in 'visit_exit_date', with: Date.new(2027, 5, 1)
      assert_selector '[data-departure-info]', text: 'Days used: 91/90'
      assert_selector '[data-departure-overstay]', text: I18n.t('days.tooltip.overstay', days: 1)
      find('#max-stay-info .exit-date-link').click
      assert_selector '[data-departure-info]', text: 'Days used: 90/90'
      assert_no_selector '[data-departure-overstay]'
      choose_visit_country('Australia')
      assert_no_selector '#entry-date-info'
      choose_visit_country('Germany')
      assert_selector '[data-departure-info]', text: 'Days used: 90/90'
      fill_in 'visit_entry_date', with: Date.new(2027, 4, 2)
      fill_in 'visit_exit_date', with: Date.new(2027, 5, 1)
      assert_selector '#max-stay-info', text: '30 days until May 1, 2027'
      assert_selector '[data-departure-info]', text: 'Days used: 90/90'
      within('#visitModal') { click_button 'Cancel' }
      assert_no_selector '.modal-backdrop'

      visit '/en/my/visits'
      find('.trips-table tbody tr', text: '01 Apr 2027').find('.edit-visit-link').click
      assert_selector '#max-stay-info', text: '30 days until April 30, 2027'
      assert_selector '[data-departure-info]', text: 'Days used: 90/90'
      assert_equal '2027-04-01', find('#visit_entry_date').value
    ensure
      page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    end
  end

  test 'mobile fields are outlined and one information panel follows the entry date' do
    page.current_window.resize_to(390, 844)
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_no_selector '#calendar-day-info'
    assert_selector '#entry-date-info', text: I18n.t('visits.entry_info')
    assert_selector '#max-stay-info', text: 'July 10, 2027'
    %w[visit_entry_date visit_exit_date visit_country_search].each do |id|
      style = page.evaluate_script(<<~JS, id)
        (function(id) {
          const css = getComputedStyle(document.getElementById(id));
          return [css.borderTopWidth, css.borderRightWidth, css.borderBottomWidth, css.borderLeftWidth, css.backgroundColor];
        })(arguments[0])
      JS
      assert_equal ['1px', '1px', '1px', '1px', 'rgb(255, 255, 255)'], style
    end
    fill_in 'visit_entry_date', with: Date.new(2027, 4, 20)
    fill_in 'visit_exit_date', with: Date.new(2027, 4, 20)
    assert_selector '#max-stay-info', text: 'July 18, 2027'
    within('#visitModal') { assert_no_text 'July 10, 2027' }
    assert_no_selector '#calendar-day-info'
  ensure
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    page.current_window.resize_to(1400, 1000)
  end

  test 'narrow visa date controls fit in one row in every language' do
    visa_user_login
    page.current_window.resize_to(320, 568)
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: 320, height: 568, deviceScaleFactor: 1, mobile: true)
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: true, maxTouchPoints: 1)
    I18n.available_locales.each do |locale|
      visit "/#{locale}/my/days?year=2027&month=4&day=12"
      find('[data-date="2027-04-12"]').click
      assert_selector 'form[data-visit-form-initialized="true"]'
      choose_visit_country(CountryCatalog.find_by_code('DE', locale: locale).name)
      find('[data-visit-add-visa]').click
      assert_selector 'form[data-inline-visa-form="true"]'
      positions = page.evaluate_script("Array.from(document.querySelectorAll('[aria-labelledby=\"visa-start-date-label\"] select')).map(el => el.getBoundingClientRect().top)")
      assert_equal 3, positions.length
      assert_in_delta positions.min, positions.max, 1
      assert page.evaluate_script("document.querySelector('#visitModal .modal-content').scrollWidth <= document.querySelector('#visitModal .modal-content').clientWidth")
      assert page.evaluate_script("document.querySelector('#saveVisitButton').getBoundingClientRect().bottom <= innerHeight")
      find('#visitModal').send_keys(:escape)
      assert_selector '#visitModal.show form[data-visit-form]'
    end
  ensure
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: false)
    page.current_window.resize_to(1400, 1000)
  end

  test 'entry warnings replace an exhausted allowance on mobile and desktop' do
    visit new_user_session_path(locale: :en)
    fill_in 'Email', with: users(:BigVisits).email
    fill_in 'Password', with: 'password'
    click_button 'Log in'
    assert_current_path private_visits_path(locale: :en)

    [390, 1400].each do |width|
      page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 844, deviceScaleFactor: 1, mobile: width == 390)
      visit '/en/my/days?year=2016&month=2&day=10'
      find('[data-date="2016-02-10"]').click
      assert_selector '#entry-date-info [data-entry-overstay]', text: I18n.t('days.tooltip.overstay', days: 1373)
      assert_equal '2016-02-10', find('#visit_entry_date').value
      assert_no_selector '#calendar-day-info'
      assert_no_selector '[data-entry-allowance]'
      fill_in 'visit_entry_date', with: Date.new(2016, 2, 1)
      assert_selector '#entry-date-info [data-entry-wait]', text: I18n.t('days.tooltip.wait', days: 148)
      assert_no_selector '[data-entry-allowance]'
    end
  ensure
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    page.current_window.resize_to(1400, 1000)
  end

  test 'closing an edit retains day context for a later shared-date chooser' do
    user_login
    [390, 1400].each do |width|
      page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 844, deviceScaleFactor: 1, mobile: width == 390)
      visit '/en/my/days?year=2014&month=3&day=10'
      find('[data-date="2014-03-10"]').click
      assert_selector '#visitModal.show form[data-visit-form]'
      within('#visitModal') { click_button 'Cancel' }
      assert_no_selector '.modal-backdrop'
      find('[data-date="2014-03-22"]').click
      assert_selector '#calendar-visit-form button', count: 2
      assert_selector '#calendar-day-info-date', text: I18n.l(Date.new(2014, 3, 22), format: :long)
      assert_selector '#calendar-day-info-content', text: 'Days used:'
      find('#calendar-visit-form button', text: 'Germany').click
      assert_selector '#visit_country_search', visible: true
      assert_equal 'DE', find('#visit_country_code', visible: :all).value
      assert_no_selector '#calendar-day-info'
    end
  ensure
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    page.current_window.resize_to(1400, 1000)
  end
end
