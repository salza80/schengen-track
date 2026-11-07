require 'test_helper'

class VisitVisaFlowBrowserTest < JavascriptIntegrationTest
  ['calendar', 'trips'].product([390, 1400]).each do |view, width|
    test "#{view} at #{width}px adds a visa and preserves the unsaved visit through validation and Back" do
      page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 844, deviceScaleFactor: 1, mobile: width == 390)
      page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: width == 390, maxTouchPoints: 1)
      visa_user_login
      if view == 'calendar'
        visit '/en/my/days?year=2027&month=4&day=12'
        find('[data-date="2027-04-12"]').click
      else
        visit '/en/my/visits'
        find('[data-action="add-visit"]', match: :first).click
      end
      assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
      fill_in 'visit_entry_date', with: Date.new(2027, 4, 12)
      fill_in 'visit_exit_date', with: Date.new(2027, 4, 16)
      choose_visit_country('Germany')
      assert_selector '#entry-date-info', text: I18n.t('visits.no_visa_for_date')
      page.execute_script("window.popupDocumentMarker = 'original'; window.originalVisitForm = document.querySelector('form[data-visit-form]')")
      find('[data-visit-add-visa]').click
      assert_selector '#visitModal form[data-inline-visa-form="true"]'
      assert_selector '#visa_start_date_1i:focus'
      assert_equal '2027', find('#visa_start_date_1i').value
      select 'January', from: 'visa_end_date_2i'
      click_button 'Save'
      assert_selector '#visitModal .alert-danger'
      assert_selector '#visa_start_date_1i:focus'
      assert_no_selector '#saveVisitButton[disabled]'
      click_button 'Back'
      assert_selector '#visitModal.show form[data-visit-form]'
      assert_equal '2027-04-12', find('#visit_entry_date').value
      assert_equal '2027-04-16', find('#visit_exit_date').value
      assert_equal 'DE', find('#visit_country_code', visible: :all).value
      assert page.evaluate_script("window.originalVisitForm === document.querySelector('form[data-visit-form]')")
      find('[data-visit-add-visa]').click
      assert_selector '#visitModal form[data-inline-visa-form="true"]'
      assert_difference('Visa.count', 1) do
        assert_no_difference('Visit.count') do
          click_button 'Save'
          assert_selector '#visitModal.show form[data-visit-form]'
          assert_selector '#entry-date-info', text: I18n.t('days.tooltip.valid_visa')
        end
      end
      assert_equal 'original', page.evaluate_script('window.popupDocumentMarker')
      assert_equal '2027-04-16', find('#visit_exit_date').value
      assert_no_selector '[data-visit-add-visa]'
      assert page.evaluate_script("window.originalVisitForm === document.querySelector('form[data-visit-form]')")
      assert_difference('Visit.count', 1) do
        click_button 'Save'
        assert_no_selector '#visitModal.show', wait: 10
      end
    ensure
      page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
      page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: false)
      page.current_window.resize_to(1400, 1000)
    end
  end

  test 'a cancelled visa load cannot replace the restored visit draft' do
    original_new = VisasController.instance_method(:new)
    VisasController.define_method(:new) do
      sleep 1 if request.format.json?
      original_new.bind_call(self)
    end
    visa_user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    choose_visit_country('Germany')
    find('[data-visit-add-visa]').click
    assert_selector '#calendar-visit-form', text: I18n.t('days.loading')
    click_button 'Back'
    assert_selector '#visitModal.show form[data-visit-form]'
    fill_in 'visit_exit_date', with: Date.new(2027, 4, 16)
    assert_equal 'DE', find('#visit_country_code', visible: :all).value
    assert_no_selector 'form[data-inline-visa-form]'
  ensure
    VisasController.define_method(:new, original_new) if original_new
  end

  [false, true].each do |cancel_load|
    test "a late visa save preserves a newer visa load, with Back #{cancel_load}" do
      original_new = VisasController.instance_method(:new)
      release_form = Queue.new
      form_requests = 0
      VisasController.define_method(:new) do
        original_new.bind_call(self)
        if request.format.json?
          form_requests += 1
          release_form.pop if form_requests == 2
        end
      end
      with_delayed_visa_save do |release_save|
        visa_user_login
        visit '/en/my/days?year=2027&month=4&day=12'
        find('[data-date="2027-04-12"]').click
        assert_selector 'form[data-visit-form-initialized="true"]'
        choose_visit_country('Germany')
        find('[data-visit-add-visa]').click
        assert_selector 'form[data-inline-visa-form="true"]'
        before = Visa.count
        click_button 'Save'
        assert_selector '#saveVisitButton[disabled]'
        click_button 'Back'
        assert_selector 'form[data-visit-form]'
        find('[data-visit-add-visa]').click
        assert_selector '#calendar-visit-form', text: I18n.t('days.loading')
        release_save << true
        assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
        if cancel_load
          click_button 'Back'
        else
          release_form << true
          assert_selector 'form[data-inline-visa-form="true"]'
          assert_no_selector '#calendar-day-info'
          click_button 'Back'
        end
        assert_no_selector '#calendar-day-info'
        assert_selector '#entry-date-info', text: I18n.t('days.tooltip.valid_visa'), wait: 10
        assert_no_selector '[data-visit-add-visa]'
        assert_equal 'DE', find('#visit_country_code', visible: :all).value
        assert_equal before + 1, Visa.count
      end
    ensure
      release_form << true if release_form
      VisasController.define_method(:new, original_new) if original_new
    end
  end

  [false, true].each do |open_another_draft|
    test "Trips reflects a late visa save after closing its visit, with another draft #{open_another_draft}" do
      with_delayed_visa_save do |release_save|
        visa_user_login
        initial_rows = all('.edit-visa-link', visible: :all).length
        find('[data-action="add-visit"]').click
        assert_selector 'form[data-visit-form-initialized="true"]'
        fill_in 'visit_entry_date', with: Date.new(2027, 4, 12)
        fill_in 'visit_exit_date', with: Date.new(2027, 4, 16)
        choose_visit_country('Germany')
        find('[data-visit-add-visa]').click
        assert_selector 'form[data-inline-visa-form="true"]'
        before = Visa.count
        click_button 'Save'
        assert_selector '#saveVisitButton[disabled]'
        click_button 'Back'
        assert_selector 'form[data-visit-form]'
        within('#visitModal') { click_button 'Cancel' }
        assert_no_selector '.modal-backdrop'

        if open_another_draft
          find('[data-action="add-visa"]').click
          assert_selector '#visaModal.show form'
          fill_in 'visa_no_entries', with: 5
          page.execute_script("window.newerVisaForm = document.querySelector('#visaModal form')")
        end
        release_save << true
        if open_another_draft
          # The hidden visit form's allowance request confirms the save callback ran.
          assert_selector '#visitModal [data-entry-visa-status]', text: I18n.t('days.tooltip.valid_visa'), visible: :all, wait: 10
          assert_selector '#visaModal.show'
          assert_equal '5', find('#visa_no_entries').value
          assert page.evaluate_script("window.newerVisaForm === document.querySelector('#visaModal form')")
          within('#visaModal') { click_button 'Cancel' }
        end
        assert_selector '.edit-visa-link', count: initial_rows + 1, visible: :all, wait: 10
        assert_equal before + 1, Visa.count
        assert_current_path private_visits_path(locale: :en)
      end
    end
  end

  private

  def with_delayed_visa_save
    original_create = VisasController.instance_method(:create)
    release_save = Queue.new
    VisasController.define_method(:create) do
      original_create.bind_call(self)
      release_save.pop if request.format.json?
    end
    yield release_save
  ensure
    release_save << true if release_save
    VisasController.define_method(:create, original_create) if original_create
  end
end
