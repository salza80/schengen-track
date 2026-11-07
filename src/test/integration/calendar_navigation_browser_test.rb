require 'test_helper'

class CalendarNavigationBrowserTest < JavascriptIntegrationTest
  [[320, :hi], [390, :ar], [1400, :de]].each do |width, locale|
    test "sticky year controls remain clickable below the header at #{width}px in #{locale}" do
      page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 844,
                                      deviceScaleFactor: 1, mobile: width < 768)
      visit days_path(locale: locale, year: 2027, month: 4, day: 12)
      assert_selector '[data-date="2027-04-12"].highlight-day', wait: 5
      assert_year_controls_clear_header
      cell_top = page.evaluate_script('document.querySelector(\'[data-date="2027-04-12"]\').getBoundingClientRect().top')
      nav_bottom = page.evaluate_script('document.querySelector(".calendar-year-nav").getBoundingClientRect().bottom')
      assert_operator cell_top, :>=, nav_bottom

      if width < 768
        find('.navbar-toggler').click
        assert_selector '#navbarContent.show'
        assert_year_controls_clear_header
        find('.navbar-toggler').click
        assert_no_selector '#navbarContent.show'
      end

      find('.calendar-year-nav.sticky-top .btn-next-year').click
      assert_current_path days_path(locale: locale, year: 2028)
      assert_selector '.calendar-view-container[data-selected-year="2028"]'
    ensure
      page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    end
  end

  test 'switching language keeps the selected calendar date on mobile' do
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: 390, height: 844,
                                    deviceScaleFactor: 1, mobile: true)
    visit '/en/days?year=2027&month=4&day=12'
    find('.language-select', match: :first).select('FR - Français')
    assert_current_path '/fr/days', ignore_query: true
    assert_equal({ 'year' => '2027', 'month' => '4', 'day' => '12' },
                 Rack::Utils.parse_query(URI.parse(page.current_url).query))
    assert_selector '.calendar-view-container[data-selected-year="2027"]'
    assert_selector '[data-date="2027-04-12"].highlight-day', wait: 5
  ensure
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
  end

  private

  def assert_year_controls_clear_header
    assert_selector '.calendar-year-nav.sticky-top' do
      page.evaluate_script(<<~JS)
        (function() {
          const header = document.querySelector('nav.navbar').getBoundingClientRect();
          const control = document.querySelector('.calendar-year-nav.sticky-top .btn-next-year');
          const rect = control.getBoundingClientRect();
          return rect.top >= header.bottom &&
            control.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2));
        })()
      JS
    end
  end
end
