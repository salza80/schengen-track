require 'test_helper'

class VisitsManagementTest < JavascriptIntegrationTest
  test 'user can view visits page with add button' do
    user_login
    
    visit private_visits_path(locale: :en)
    assert_text 'Trips', wait: 5
    
    # Verify Add Travel button is present
    assert has_selector?('button[data-action="add-visit"]', wait: 5)
  end

  test 'mobile trip headings keep dates and touch actions together across locales' do
    visits(:two).update!(country: countries(:USA))
    user_login

    [320, 390].each do |width|
      emulate_mobile(width)
      I18n.available_locales.each do |locale|
        visit private_visits_path(locale: locale)
        assert_selector '.trips-table .trip-country', text: countries(:USA).localized_name(locale)
        all('.trips-table tbody tr', minimum: 3).each do |row|
          assert_equal 0, row.all("td[data-title='#{I18n.t('visits.modify', locale: locale)}']", visible: :all, wait: 0).length
          assert_equal 1, row.all('.edit-visit-link', visible: :all).length
          assert_equal 1, row.all('.delete-visit-link', visible: :all).length
          refute_includes row.find('.trip-heading').text, '('

          layout = page.evaluate_script(<<~JS, row)
            (function(row) {
              const heading = row.querySelector('.trip-heading').getBoundingClientRect();
              const buttons = Array.from(row.querySelectorAll('.trip-actions a'), a => a.getBoundingClientRect());
              const country = document.createRange();
              country.selectNodeContents(row.querySelector('.trip-country'));
              const overlap = Array.from(country.getClientRects()).some(title => buttons.some(button =>
                title.left < button.right && title.right > button.left && title.top < button.bottom && title.bottom > button.top));
              return {
                targets: buttons.every(button => button.width >= 44 && button.height >= 44),
                inHeading: buttons.every(button => button.top >= heading.top && button.bottom <= heading.bottom && button.left >= heading.left && button.right <= heading.right),
                overlap: overlap,
                fits: row.scrollWidth <= row.clientWidth && row.querySelector('.trip-dates').scrollWidth <= row.querySelector('.trip-dates').clientWidth
              };
            })(arguments[0])
          JS
          assert layout['targets'], "#{locale} at #{width}px: touch targets"
          assert layout['inHeading'], "#{locale} at #{width}px: actions stay in the heading"
          refute layout['overlap'], "#{locale} at #{width}px: title and actions overlap"
          assert layout['fits'], "#{locale} at #{width}px: card fits"
        end
      end
    end
  ensure
    clear_mobile_emulation
  end

  test 'mobile heading actions open their dialogs and dates still open the calendar' do
    emulate_mobile(320)
    user_login
    row = find('.trips-table tbody tr', match: :first)
    edit = row.find('.edit-visit-link')
    edit.find('i').click
    assert_selector '#visitModal.show form[data-visit-form]'
    assert_equal visits(:one).entry_date.iso8601, find('#visit_entry_date').value
    within('#visitModal') { find('button.btn-close').click }
    assert_no_selector '#visitModal.show'
    assert_selector '.edit-visit-link:focus'
    assert_equal edit, page.active_element
    assert_current_path private_visits_path(locale: :en)

    delete = row.find('.delete-visit-link')
    delete.find('i').click
    assert_selector '#deleteModal.show'
    within('#deleteModal') { click_button 'Cancel' }
    assert_no_selector '#deleteModal.show'
    assert_selector '.delete-visit-link:focus'
    assert_equal delete, page.active_element

    row.find('.trip-dates').click
    assert_current_path private_days_path(locale: :en), ignore_query: true
    assert_equal({ 'year' => '2014', 'month' => '3', 'day' => '10' }, Rack::Utils.parse_query(URI.parse(page.current_url).query))
  ensure
    clear_mobile_emulation
  end

  test 'desktop trips retain the details and a single action column' do
    user_login
    [768, 1400].each do |width|
      page.current_window.resize_to(width, 1000)
      row = find('.trips-table tbody tr', match: :first)
      assert_no_selector '.trips-table .trip-country'
      assert row.has_text?('Germany')
      assert_equal 'table-cell', row.find('.trip-actions').style('display')['display']
      assert_equal 1, row.all('.edit-visit-link', visible: :all).length
      assert_equal 1, row.all('.delete-visit-link', visible: :all).length
      heading = row.find('.trip-heading').native.rect
      assert_operator row.find('.trip-actions').native.rect.x, :>, heading.x + heading.width
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'the visa section anchor stays below the fixed navigation' do
    visa_user_login
    [320, 1400].each do |width|
      emulate_mobile(width)
      visit private_visits_path(locale: :en, anchor: 'visas')
      assert_selector '#visas'
      assert page.evaluate_script(<<~JS)
        document.getElementById('visas').getBoundingClientRect().top >=
          document.querySelector('nav.navbar').getBoundingClientRect().bottom
      JS
    end
  ensure
    clear_mobile_emulation
  end

  private

  def emulate_mobile(width)
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 844, deviceScaleFactor: 1, mobile: true)
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: true, maxTouchPoints: 1)
  end

  def clear_mobile_emulation
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: false)
    page.current_window.resize_to(1400, 1000)
  end
end
