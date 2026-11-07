require 'test_helper'

class CalendarUxBrowserTest < JavascriptIntegrationTest
  test 'desktop hover and drag keep the range and the next ordinary click works' do
    page.current_window.resize_to(1440, 1000)
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    assert_selector '[data-date="2027-04-12"].highlight-day', wait: 3
    start_cell = find('[data-date="2027-04-12"]')
    end_cell = find('[data-date="2027-04-14"]')
    assert page.evaluate_script("matchMedia('(hover: hover) and (pointer: fine)').matches")
    start_cell.hover
    assert_selector '.tooltip.show', text: 'Days used: 0/90'
    page.driver.browser.action.move_to(start_cell.native).click_and_hold.move_to(end_cell.native).release.perform
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]', wait: 5
    assert_equal '2027-04-12', find('#visit_entry_date').value
    assert_equal '2027-04-14', find('#visit_exit_date').value
    within('#visitModal') { click_button 'Cancel' }
    assert_no_selector '#visitModal.show'
    find('[data-date="2027-04-20"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_equal '2027-04-20', find('#visit_entry_date').value
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'cancel during a delayed nationality refresh keeps the dialog closed' do
    original_index = DaysController.instance_method(:index)
    DaysController.define_method(:index) do
      sleep 2 if request.format.json?
      original_index.bind_call(self)
    end
    page.current_window.resize_to(390, 844)
    visit '/en/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show .nationality-step-form'
    select 'United States', from: 'calculator_nationality_step'
    click_button 'Continue'
    assert_selector '#calendar-visit-form', text: I18n.t('days.loading')
    within('#visitModal') { click_button 'Cancel' }
    assert_no_selector '#visitModal.show'
    assert_current_path private_days_path(locale: :en), ignore_query: true, wait: 6
    assert_no_selector '#calendar-content[aria-busy="true"]'
    assert_no_selector '#visitModal.show'
    # A new intent still loads the requested date after the cancelled continuation.
    find('[data-date="2027-04-20"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_equal '2027-04-20', find('#visit_entry_date').value
  ensure
    DaysController.define_method(:index, original_index) if original_index
    page.current_window.resize_to(1400, 1000)
  end

  test 'calendar has one Tab stop and day navigation stays in the displayed year' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    assert_selector '.day-cell[tabindex="0"]', count: 1
    cell = find('.day-cell[tabindex="0"]')
    assert_equal '2027-04-12', cell['data-date']
    cell.send_keys(:arrow_right)
    assert_selector '.day-cell[tabindex="0"]:focus[data-date="2027-04-13"]'
    find('.day-cell:focus').send_keys(:arrow_down)
    assert_selector '.day-cell:focus[data-date="2027-04-20"]'
    find('.day-cell:focus').send_keys(:home)
    assert_selector '.day-cell:focus[data-date="2027-04-18"]'
    find('.day-cell:focus').send_keys(:end)
    assert_selector '.day-cell:focus[data-date="2027-04-24"]'
    find('.day-cell:focus').send_keys(:enter)
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    find('#visitModal').send_keys(:escape)
    assert_no_selector '#visitModal.show'
    assert_selector '.day-cell:focus[data-date="2027-04-24"]'
    assert_selector '.day-cell[tabindex="0"]', count: 1
    assert_selector '.calendar-view-container[data-selected-year="2027"]'
  end

  test 'calendar arrow keys follow the visual grid inside an RTL page' do
    user_login
    visit '/ar/my/days?year=2027&month=4&day=12'
    cell = find('.day-cell[tabindex="0"]')
    original_x = cell.native.rect.x
    assert_equal 'rtl', find('html')['dir']
    assert_equal 'ltr', page.evaluate_script("getComputedStyle(document.querySelector('.calendar-grid')).direction")
    cell.send_keys(:arrow_right)
    assert_selector '.day-cell:focus[data-date="2027-04-13"]'
    assert_operator find('.day-cell:focus').native.rect.x, :>, original_x
    find('.day-cell:focus').send_keys(:arrow_left)
    assert_selector '.day-cell:focus[data-date="2027-04-12"]'
    find('.day-cell:focus').send_keys(:home)
    assert_selector '.day-cell:focus[data-date="2027-04-11"]'
    find('.day-cell:focus').send_keys(:end)
    assert_selector '.day-cell:focus[data-date="2027-04-17"]'
    assert_selector '.day-cell[tabindex="0"]', count: 1
  end

  test 'mouse range selection remains available on a touch capable desktop' do
    user_login
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: true, maxTouchPoints: 1)
    visit '/en/my/days?year=2027&month=4&day=12'
    assert_operator page.evaluate_script('navigator.maxTouchPoints'), :>, 0
    assert_selector '[data-date="2027-04-12"].highlight-day', wait: 3
    start_cell = find('[data-date="2027-04-12"]')
    end_cell = find('[data-date="2027-04-14"]')
    page.driver.browser.action.move_to(start_cell.native).click_and_hold.move_to(end_cell.native).release.perform
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_equal '2027-04-12', find('#visit_entry_date').value
    assert_equal '2027-04-14', find('#visit_exit_date').value
  ensure
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: false)
  end

  test 'losing window focus cancels an unfinished mouse range' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    start_cell = find('[data-date="2027-04-12"]')
    end_cell = find('[data-date="2027-04-14"]')
    page.driver.browser.action.move_to(start_cell.native).click_and_hold.move_to(end_cell.native).perform
    assert_selector '.day-cell.selecting', count: 3
    page.execute_script("window.dispatchEvent(new Event('blur'))")
    assert_no_selector '.day-cell.selecting'
    page.driver.browser.action.move_to(find('[data-date="2027-04-15"]').native).release.perform
    assert_no_selector '.day-cell.selecting'
    assert_no_selector '#visitModal.show'
    find('[data-date="2027-04-20"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_equal '2027-04-20', find('#visit_entry_date').value
    assert_equal '2027-04-20', find('#visit_exit_date').value
  end

  test 'a calendar refresh preserves a mouse range and its focus return target' do
    original_index = DaysController.instance_method(:index)
    release_refresh = Queue.new
    DaysController.define_method(:index) do
      original_index.bind_call(self)
      release_refresh.pop if request.format.json?
    end
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    assert_selector '[data-date="2027-04-12"].highlight-day', wait: 3
    page.execute_script('window.CalendarRefresh.refresh()')
    assert_selector '#calendar-content[aria-busy="true"]'
    start_cell = find('[data-date="2027-04-12"]')
    end_cell = find('[data-date="2027-04-14"]')
    page.driver.browser.action.move_to(start_cell.native).click_and_hold.move_to(end_cell.native).perform
    assert_selector '.day-cell.selecting', count: 3
    release_refresh << true
    assert_no_selector '#calendar-content[aria-busy="true"]'
    assert_selector '.day-cell.selecting', count: 3
    page.driver.browser.action.release.perform
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_equal '2027-04-12', find('#visit_entry_date').value
    assert_equal '2027-04-14', find('#visit_exit_date').value
    within('#visitModal') { click_button 'Cancel' }
    assert_no_selector '.modal-backdrop'
    assert_selector '.day-cell:focus[data-date="2027-04-12"]'
  ensure
    release_refresh << true if release_refresh
    DaysController.define_method(:index, original_index) if original_index
  end

  test 'native dates allow same day stays and prevent a departure before arrival' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_selector '.visit-duration', text: '1 day, including arrival and departure.'
    choose_visit_country('Germany')
    find('#max-stay-info .exit-date-link').click
    assert_equal '2027-07-10', find('#visit_exit_date').value
    assert_selector '.visit-duration', text: '90 days, including arrival and departure.'
    fill_in 'visit_exit_date', with: Date.iso8601('2027-04-11')
    assert page.evaluate_script("document.getElementById('visit_exit_date').validity.rangeUnderflow")
    assert_no_difference('Visit.count') do
      click_button 'Save'
      assert_selector '#visitModal.show'
      assert_no_selector '#saveVisitButton[disabled]'
    end
    fill_in 'visit_exit_date', with: Date.iso8601('2027-04-12')
    assert_selector '.visit-duration', text: '1 day, including arrival and departure.'
    assert_difference('Visit.count', 1) do
      click_button 'Save'
      assert_no_selector '#visitModal.show'
      assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
      assert_no_selector '#calendar-content[aria-busy="true"]', wait: 10
    end
    assert_selector '.day-cell[tabindex="0"]', count: 1
  end

  test 'a slow save and recalculation show their separate progress states' do
    original_update = VisitsController.instance_method(:update)
    original_index = DaysController.instance_method(:index)
    VisitsController.define_method(:update) do
      sleep 1 if request.format.json?
      original_update.bind_call(self)
    end
    DaysController.define_method(:index) do
      sleep 2 if request.format.json?
      original_index.bind_call(self)
    end
    user_login
    visit '/en/my/days?year=2014&month=3&day=10'
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-21')
    click_button 'Save'
    assert_selector '#saveVisitButton[disabled]', text: I18n.t('days.saving')
    assert_selector '#calendar-feedback', text: I18n.t('days.updating'), wait: 5
    assert_selector '#calendar-content[aria-busy="true"]'
    assert_equal Date.new(2014, 3, 21), visits(:one).reload.exit_date
    find('[data-date="2014-03-20"]').send_keys(:arrow_right)
    assert_selector '.day-cell:focus[data-date="2014-03-21"]'
    assert_no_selector '#calendar-content[aria-busy="true"]', wait: 10
    assert_selector '#calendar-feedback', text: I18n.t('days.saved')
    assert_selector '.day-cell:focus[tabindex="0"][data-date="2014-03-21"]'
    assert_selector '.day-cell[tabindex="0"]', count: 1
  ensure
    VisitsController.define_method(:update, original_update) if original_update
    DaysController.define_method(:index, original_index) if original_index
  end

  test 'a failed save shows an inline error and keeps the entered values for retry' do
    original_update = VisitsController.instance_method(:update)
    VisitsController.define_method(:update) { render json: {}, status: :service_unavailable }
    user_login
    visit '/en/my/days?year=2014&month=3&day=10'
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-21')
    click_button 'Save'
    assert_selector '#visitModal.show .calendar-save-error', text: I18n.t('days.save_error')
    assert_no_selector '#saveVisitButton[disabled]'
    assert_equal '2014-03-21', find('#visit_exit_date').value
    assert_equal 'DE', find('#visit_country_code', visible: :all).value
    assert_equal Date.new(2014, 3, 22), visits(:one).reload.exit_date
    VisitsController.define_method(:update, original_update)
    click_button 'Save'
    assert_no_selector '#visitModal.show', wait: 10
    assert_equal Date.new(2014, 3, 21), visits(:one).reload.exit_date
  ensure
    VisitsController.define_method(:update, original_update) if original_update
  end

  test 'an older totals response cannot replace a newer saved edit' do
    original_index = DaysController.instance_method(:index)
    release_first = Queue.new
    first_refresh = true
    DaysController.define_method(:index) do
      hold_response = request.format.json? && first_refresh
      first_refresh = false if hold_response
      original_index.bind_call(self)
      release_first.pop if hold_response
    end
    user_login
    visit '/en/my/days?year=2014&month=3&day=10'
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-21')
    click_button 'Save'
    assert_selector '#calendar-feedback', text: I18n.t('days.updating')
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-20')
    click_button 'Save'
    assert_selector '.day-cell.no-travel[data-date="2014-03-21"]', wait: 10
    page.execute_script(<<~JS)
      jQuery(document).on('ajaxComplete.review', function(event, xhr, settings) {
        if (settings.url.includes('/my/days.json')) {
          document.body.dataset.oldRefreshCompleted = 'true';
          jQuery(document).off('ajaxComplete.review');
        }
      });
    JS
    release_first << true
    assert_selector 'body[data-old-refresh-completed="true"]', wait: 10
    assert_selector '.day-cell.no-travel[data-date="2014-03-21"]'
    assert_equal Date.new(2014, 3, 20), visits(:one).reload.exit_date
  ensure
    release_first << true if release_first
    DaysController.define_method(:index, original_index) if original_index
  end

  test 'a pending save refreshes the calendar after its dialog form has been replaced' do
    original_update = VisitsController.instance_method(:update)
    release_save = Queue.new
    VisitsController.define_method(:update) do
      original_update.bind_call(self)
      release_save.pop if request.format.json?
    end
    user_login
    visit '/en/my/days?year=2014&month=3&day=10'
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-20')
    page.execute_script(<<~JS)
      jQuery(document).on('ajaxComplete.review', function(event, xhr, settings) {
        if (settings.type === 'POST' && settings.url.includes('/visits/')) {
          document.body.dataset.pendingSaveCompleted = 'true';
          jQuery(document).off('ajaxComplete.review');
        }
      });
    JS
    click_button 'Save'
    assert_selector '#saveVisitButton[disabled]', text: I18n.t('days.saving')
    within('#visitModal') { click_button 'Cancel' }
    assert_no_selector '#visitModal.show'
    find('[data-date="2014-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    choose_visit_country('India')
    release_save << true
    assert_selector 'body[data-pending-save-completed="true"]', wait: 10
    assert_selector '.day-cell.no-travel[data-date="2014-03-21"]', wait: 10
    assert_selector '#visitModal.show'
    assert_equal '2014-04-12', find('#visit_entry_date').value
    assert_equal 'IN', find('#visit_country_code', visible: :all).value
    assert_equal Date.new(2014, 3, 20), visits(:one).reload.exit_date
  ensure
    release_save << true if release_save
    VisitsController.define_method(:update, original_update) if original_update
  end

  [:for_date, :edit].each do |action|
    test "a failed calendar #{action} lookup can retry without showing an add form" do
      original_action = VisitsController.instance_method(action)
      fail_once = true
      VisitsController.define_method(action) do
        if request.format.json? && fail_once
          fail_once = false
          render json: {}, status: :service_unavailable
        else
          original_action.bind_call(self)
        end
      end
      user_login
      visit '/en/my/days?year=2014&month=3&day=10'
      find('[data-date="2014-03-10"]').click
      assert_selector '#calendar-visit-form [role="alert"]', text: I18n.t('days.form_error')
      assert_no_selector '#calendar-visit-form form'
      assert_selector '#saveVisitButton[disabled]'
      within('#calendar-visit-form') { click_button I18n.t('days.retry') }
      assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
      assert_equal Date.new(2014, 3, 10).iso8601, find('#visit_entry_date').value
      assert_equal 'DE', find('#visit_country_code', visible: :all).value
      assert_selector '#visitModal', text: I18n.t('visits.edit_title')
    ensure
      VisitsController.define_method(action, original_action) if original_action
    end
  end
end
