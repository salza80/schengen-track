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

  test 'country search filters directly and supports keyboard selection and cancellation' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_country_search', with: 'GERM'
    assert_selector '#visit_country_results [role="option"]', text: 'Germany'
    find('#visit_country_search').send_keys(:arrow_down, :enter)
    assert_equal 'Germany', find('#visit_country_search').value
    assert_equal 'DE', find('#visit_country_id', visible: :all).value
    assert_selector '#visit_country_search[aria-expanded="false"]'
    fill_in 'visit_country_search', with: 'no such country'
    assert_selector '#visit_country_status', text: I18n.t('visits.country_no_matches')
    assert_equal '', find('#visit_country_id', visible: :all).value
    assert page.evaluate_script("document.getElementById('visit_country_search').validity.customError")
    find('#visit_country_search').send_keys(:escape)
    assert_selector '#visit_country_search[aria-expanded="false"]'
    assert_selector '#visitModal.show'
    find('#visit_country_search').send_keys(:escape)
    assert_no_selector '#visitModal.show'
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
    assert_equal 'DE', find('#visit_country_id', visible: :all).value
    assert_equal Date.new(2014, 3, 22), visits(:one).reload.exit_date
    VisitsController.define_method(:update, original_update)
    click_button 'Save'
    assert_no_selector '#visitModal.show', wait: 10
    assert_equal Date.new(2014, 3, 21), visits(:one).reload.exit_date
  ensure
    VisitsController.define_method(:update, original_update) if original_update
  end
end
