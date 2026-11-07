require 'test_helper'

class CountryPickerBrowserTest < JavascriptIntegrationTest
  test 'country search filters directly and supports keyboard selection and cancellation' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_country_search', with: 'GERM'
    assert_selector '#visit_country_results [role="option"]', text: 'Germany'
    find('#visit_country_search').send_keys(:arrow_down, :enter)
    assert_equal 'Germany', find('#visit_country_search').value
    assert_equal 'DE', find('#visit_country_code', visible: :all).value
    assert_selector '#visit_country_search[aria-expanded="false"]'
    fill_in 'visit_country_search', with: 'no such country'
    assert_selector '#visit_country_status', text: I18n.t('visits.country_no_matches')
    assert_equal '', find('#visit_country_code', visible: :all).value
    assert page.evaluate_script("document.getElementById('visit_country_search').validity.customError")
    find('#visit_country_search').send_keys(:escape)
    assert_selector '#visit_country_search[aria-expanded="false"]'
    assert_selector '#visitModal.show'
    find('#visit_country_search').send_keys(:escape)
    assert_no_selector '#visitModal.show'
  end

  test 'country search supports Turkish case folding and French accents' do
    user_login
    [['tr', 'ital', 'İtalya', 'IT'], ['fr', 'etats', 'États-Unis', 'US']].each do |locale, query, name, code|
      visit "/#{locale}/my/days?year=2027&month=4&day=12"
      find('[data-date="2027-04-12"]').click
      assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
      fill_in 'visit_country_search', with: query
      find('#visit_country_results [role="option"]', text: name, exact_text: true).click
      assert_equal code, find('#visit_country_code', visible: :all).value
    end
  end

  test 'country search leaves composition Enter to the input method' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_country_search', with: 'ger'
    page.execute_script(<<~JS)
      document.getElementById('visit_country_search').dispatchEvent(new KeyboardEvent('keydown', {
        key: 'Enter', isComposing: true, bubbles: true, cancelable: true
      }));
    JS
    assert_equal 'ger', find('#visit_country_search').value
    assert_equal '', find('#visit_country_code', visible: :all).value
    assert_selector '#visit_country_search[aria-expanded="true"]'
  end


  test 'filtering countries starts the result list at the top' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_country_search', with: ''
    find('#visit_country_search').click
    assert_selector '#visit_country_results [role="option"]', minimum: 100
    page.execute_script("document.getElementById('visit_country_results').scrollTop = 300")
    assert_operator page.evaluate_script("document.getElementById('visit_country_results').scrollTop"), :>, 0
    fill_in 'visit_country_search', with: 'a'
    assert_equal 0, page.evaluate_script("document.getElementById('visit_country_results').scrollTop")
  end

  ['calendar', 'trips'].each do |view|
    test "#{view} creates and edits countries across continents without a dependent select" do
      user_login
      if view == 'calendar'
        visit '/en/my/days?year=2027&month=4&day=12'
        find('[data-date="2027-04-12"]').click
      else
        visit '/en/my/visits'
        find('[data-action="add-visit"]', match: :first).click
      end
      assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
      assert_no_selector '[data-continent-selector]', visible: :all
      fill_in 'visit_entry_date', with: Date.iso8601('2027-04-12')
      fill_in 'visit_exit_date', with: Date.iso8601('2027-04-14')
      choose_visit_country('Germany')
      choose_visit_country('India')
      assert_equal 'IN', find('#visit_country_code', visible: :all).value
      click_button 'Save'
      assert_no_selector '#visitModal.show', wait: 10
      if view == 'calendar'
        assert_selector '[data-date="2027-04-12"] .day-country', text: 'India', wait: 10
        find('[data-date="2027-04-12"]').click
      else
        assert_selector '.edit-visit-link', wait: 10
        record = visits(:one).person.visits.find_by!(entry_date: Date.new(2027, 4, 12))
        find(".edit-visit-link[data-visit-id='#{record.id}']").click
      end
      assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
      assert_equal 'India', find('#visit_country_search').value
      assert_equal 'IN', find('#visit_country_code', visible: :all).value
      choose_visit_country('Australia')
      click_button 'Save'
      assert_no_selector '#visitModal.show', wait: 10
      if view == 'calendar'
        assert_selector '[data-date="2027-04-12"] .day-country', text: 'Australia', wait: 10
      else
        assert_selector 'tr', text: 'Australia', wait: 10
      end
      record = visits(:one).person.visits.find_by!(entry_date: Date.new(2027, 4, 12))
      assert_equal countries(:Australia), record.country
    end
  end

  test 'opening the Trips dialog preserves country input started during its animation' do
    user_login
    visit '/en/my/visits'
    page.execute_script(<<~JS)
      document.querySelector('#visitModal .modal-dialog').style.transitionDuration = '1s';
      jQuery('#visitModal').one('shown.bs.modal', function() {
        document.body.dataset.countryDialogReady = 'true';
      });
    JS
    find('[data-action="add-visit"]', match: :first).click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_country_search', with: 'India'
    assert_selector 'body[data-country-dialog-ready="true"]', wait: 5
    assert_selector '#visit_country_search:focus'
    assert_equal 'visit_country_search', page.evaluate_script('document.activeElement.id')
    assert_selector '#visit_country_results [role="option"]', text: 'India', exact_text: true
  end

  test 'Enter never commits an unhighlighted country suggestion' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    find('#visit_country_search').click
    find('#visit_country_search').send_keys(:enter)
    assert_equal '', find('#visit_country_search').value
    assert_equal '', find('#visit_country_code', visible: :all).value
    fill_in 'visit_country_search', with: 'ger'
    find('#visit_country_search').send_keys(:enter)
    assert_equal 'ger', find('#visit_country_search').value
    assert_equal '', find('#visit_country_code', visible: :all).value
    find('#visit_country_search').send_keys(:arrow_down, :enter)
    assert_equal 'Germany', find('#visit_country_search').value
    assert_equal 'DE', find('#visit_country_code', visible: :all).value
  end

  test 'country search prioritizes name prefixes and exact ISO country codes' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_country_search', with: 'ger'
    assert_equal 'Germany', first('#visit_country_results [role="option"]').text
    assert_selector '#visit_country_results [role="option"]', text: 'Algeria', exact_text: true
    fill_in 'visit_country_search', with: 'us'
    assert_equal 'United States', first('#visit_country_results [role="option"]').text
    find('#visit_country_search').send_keys(:arrow_down, :enter)
    assert_equal 'US', find('#visit_country_code', visible: :all).value
    fill_in 'visit_country_search', with: 'india'
    find('#visit_country_search').send_keys(:enter)
    assert_equal 'India', find('#visit_country_search').value
    assert_equal 'IN', find('#visit_country_code', visible: :all).value
  end

  test 'a selected country can be cleared and replaced without submitting the visit' do
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    choose_visit_country('Germany')
    assert_no_difference('Visit.count') do
      button = find('[data-country-clear]')
      assert_equal I18n.t('visits.country_clear'), button['aria-label']
      button.send_keys(:enter)
      assert_equal '', find('#visit_country_search').value
      assert_equal '', find('#visit_country_code', visible: :all).value
      assert_selector '#visit_country_search:focus'
      assert_selector '#visit_country_results [role="option"]', minimum: 100
      assert_no_selector '[data-country-clear]'
    end
    choose_visit_country('India')
    assert_equal 'IN', find('#visit_country_code', visible: :all).value
  end

  test 'allowance hint updates do not move the country control on mobile' do
    original_info = VisitsController.instance_method(:max_stay_info)
    VisitsController.define_method(:max_stay_info) do
      sleep 1
      original_info.bind_call(self)
    end
    page.current_window.resize_to(390, 844)
    user_login
    visit '/en/my/days?year=2027&month=4&day=12'
    find('[data-date="2027-04-12"]').click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    assert_selector '#max-stay-info .exit-date-link', wait: 10
    top = page.evaluate_script("document.getElementById('visit_country_search').getBoundingClientRect().top")
    choose_visit_country('Germany')
    assert_in_delta top, page.evaluate_script("document.getElementById('visit_country_search').getBoundingClientRect().top"), 1
    assert_selector '#max-stay-info .exit-date-link', wait: 10
    assert_in_delta top, page.evaluate_script("document.getElementById('visit_country_search').getBoundingClientRect().top"), 1
  ensure
    VisitsController.define_method(:max_stay_info, original_info) if original_info
    page.current_window.resize_to(1400, 1000)
  end
end
