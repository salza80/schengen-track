require 'test_helper'

Capybara.register_driver :selenium_csp do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  %w[--headless=new --no-sandbox --disable-dev-shm-usage --disable-gpu --window-size=1400,1000].each do |argument|
    options.add_argument(argument)
  end
  options.binary = ENV['CHROME_BIN'] if ENV['CHROME_BIN'].present?
  service_options = {}
  service_options[:path] = ENV['CHROMEDRIVER_PATH'] if ENV['CHROMEDRIVER_PATH'].present?
  service = Selenium::WebDriver::Service.chrome(**service_options)
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

class DocumentContentSecurityBrowserTest < JavascriptIntegrationTest
  def setup
    super
    # The general browser driver disables web security; this one must enforce CSP.
    Capybara.current_driver = :selenium_csp
  end

  test 'a first mobile calendar trip keeps its document and visible date through nationality and saves' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: true, maxTouchPoints: 1)
    page.current_window.resize_to(390, 844)
    visit '/en/days?year=2027&month=4&day=12'
    cell = find('[data-date="2027-04-12"]')
    page.execute_script(<<~JS, cell)
      document.dispatchEvent(new Event('pointerdown'));
      arguments[0].scrollIntoView({ block: 'center', behavior: 'instant' });
      window.calendarDocumentMarker = 'original';
    JS
    initial_top = page.evaluate_script('arguments[0].getBoundingClientRect().top', cell)
    touch_tap(cell)
    assert_selector '#visitModal.show .nationality-step-form'
    assert_selector '#calendar-day-info-date', text: 'April 12, 2027'
    assert_selector '#calendar-day-info-content', text: 'Days used: 0/90'
    assert_no_selector '.tooltip.show'
    within '#visitModal' do
      select 'United States', from: 'calculator_nationality_step'
      click_button I18n.t('common.continue')
    end
    assert_selector '#visitModal.show form[data-calendar-visit-form="true"]', wait: 10
    assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
    assert_no_selector 'meta[name="csp-nonce"]', visible: :all
    assert_in_delta initial_top, page.evaluate_script('document.querySelector(\'[data-date="2027-04-12"]\').getBoundingClientRect().top'), 2
    assert_equal '2027-04-12', find('#visit_entry_date').value
    assert_no_selector '#calendar-day-info'
    assert_selector '#entry-date-info', text: 'Days used: 0/90'
    fill_in 'visit_exit_date', with: Date.iso8601('2027-04-14')
    fill_in 'visit_country_search', with: 'Germany'
    touch_tap(find('#visit_country_results [role="option"]', text: 'Germany', exact_text: true))
    assert_equal 'DE', find('#visit_country_code', visible: :all).value
    touch_tap(find('[data-country-clear]'))
    assert_equal '', find('#visit_country_code', visible: :all).value
    assert_selector '#visit_country_search:focus'
    fill_in 'visit_country_search', with: 'Germany'
    touch_tap(find('#visit_country_results [role="option"]', text: 'Germany', exact_text: true))
    click_button I18n.t('common.save')
    assert_no_selector '#visitModal.show', wait: 10
    assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
    assert_selector '[data-date="2027-04-14"] .day-count strong', text: '3'
    assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
    assert_current_path private_days_path(locale: :en), ignore_query: true
    assert_in_delta initial_top, page.evaluate_script('document.querySelector(\'[data-date="2027-04-12"]\').getBoundingClientRect().top'), 2

    # Refreshed cells remain interactive; an edit updates subsequent counts too.
    page.execute_script('document.querySelector(\'[data-date="2027-04-12"]\').click()')
    assert_selector '#visitModal.show', text: I18n.t('visits.edit_title'), wait: 10
    fill_in 'visit_exit_date', with: Date.iso8601('2027-04-15')
    click_button I18n.t('common.save')
    assert_no_selector '#visitModal.show', wait: 10
    assert_selector '[data-date="2027-04-15"] .day-count strong', text: '4', wait: 10
    assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
    assert_in_delta initial_top, page.evaluate_script('document.querySelector(\'[data-date="2027-04-12"]\').getBoundingClientRect().top'), 2
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: false)
    page.current_window.resize_to(1400, 1000)
  end

  test 'calendar validation keeps day information and the entered form until corrected' do
    user_login
    visit '/en/my/days?year=2014&month=3&day=10'
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-calendar-visit-form="true"]', wait: 10
    page.execute_script("window.calendarDocumentMarker = 'original'")
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-23')
    click_button I18n.t('common.save')
    assert_selector '#calendar-visit-form .alert-danger', wait: 10
    assert_no_selector '#calendar-day-info'
    assert_selector '#entry-date-info', text: I18n.t('visits.entry_info')
    assert_equal '2014-03-23', find('#visit_exit_date').value
    assert_equal 'DE', find('#visit_country_code', visible: :all).value
    assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
    # Arrow keys in a date input must not trigger the calendar's year navigation.
    page.execute_script("document.getElementById('visit_exit_date').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }))")
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-21')
    click_button I18n.t('common.save')
    assert_no_selector '#visitModal.show', wait: 10
    assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
    assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
  end

  test 'a first visa can be added inside a nonce-free calendar without losing the trip' do
    original_protection = ActionController::Base.allow_forgery_protection
    original_limiter = RateLimiters::DatabaseFixedWindow.instance_method(:call)
    # Browser fixtures share a connection across request threads. Keep this CSP
    # test independent of concurrent raw-PG quota queries; quota behavior has its
    # own integration coverage.
    RateLimiters::DatabaseFixedWindow.define_method(:call) do
      RateLimiters::DatabaseFixedWindow::Result.new(allowed?: true)
    end
    ActionController::Base.allow_forgery_protection = true
    page.current_window.resize_to(390, 844)
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: true, maxTouchPoints: 1)
    visit '/en/days?year=2027&month=4&day=12'
    cell = find('[data-date="2027-04-12"]')
    page.execute_script(<<~JS, cell)
      document.dispatchEvent(new Event('pointerdown'));
      arguments[0].scrollIntoView({ block: 'center', behavior: 'instant' });
    JS
    touch_tap(cell)
    assert_selector '#visitModal.show .nationality-step-form'
    select 'India', from: 'calculator_nationality_step'
    click_button 'Continue'
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]'
    fill_in 'visit_exit_date', with: Date.new(2027, 4, 16)
    choose_visit_country('Germany')
    page.execute_script("window.popupDocumentMarker = 'original'")
    touch_tap(find('[data-visit-add-visa]'))
    assert_selector '#visitModal form[data-inline-visa-form="true"]'
    assert_no_selector 'meta[name="csp-nonce"]', visible: :all
    assert_difference(['User.count', 'Person.count', 'Visa.count'], 1) do
      assert_no_difference('Visit.count') do
        click_button 'Save'
        assert_selector '#visitModal.show form[data-visit-form]'
        assert_selector '#entry-date-info', text: I18n.t('days.tooltip.valid_visa'), wait: 10
      end
    end
    assert_equal '2027-04-16', find('#visit_exit_date').value
    assert_equal 'DE', find('#visit_country_code', visible: :all).value
    assert_equal 'original', page.evaluate_script('window.popupDocumentMarker')
    assert_selector '#visit_country_search:focus'
    assert_difference('Visit.count', 1) do
      click_button 'Save'
      assert_no_selector '#visitModal.show', wait: 10
      assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
    end
  ensure
    ActionController::Base.allow_forgery_protection = original_protection
    RateLimiters::DatabaseFixedWindow.define_method(:call, original_limiter) if original_limiter
    page.driver.browser.execute_cdp('Emulation.setTouchEmulationEnabled', enabled: false)
    page.current_window.resize_to(1400, 1000)
  end

  [320, 390, 1400].each do |width|
    I18n.available_locales.each do |locale|
      test "#{locale} border-day visit choices use localized dates at #{width}px" do
        user_login
        page.current_window.resize_to(width, 1000)
        page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: width, height: 1000,
                                        deviceScaleFactor: 1, mobile: width < 768)
        calendar_path = private_days_path(locale: locale, year: 2014, month: 3, day: 22)
        visit calendar_path
        assert_current_path calendar_path
        assert_selector '.calendar-view-container[data-selected-year="2014"]'
        assert_equal width, page.evaluate_script('innerWidth')
        assert_calendar_grid_fits
        country_label = I18n.t('days.country_labels.country_change', locale: locale,
                               entered_country: countries(:Australia).localized_name(locale),
                               exited_country: countries(:Germany).localized_name(locale))
        assert_selector '[data-date="2014-03-22"] .day-country', text: country_label
        assert_includes find('[data-date="2014-03-22"]')['data-bs-title'], country_label
        find('[data-date="2014-03-22"]').click
        assert_selector '#visitModal.show #calendar-day-info'
        assert_selector '#calendar-day-info', text: country_label
        within '#calendar-visit-form' do
          assert_selector 'button', count: 2, wait: 10
          date_range = [I18n.l(visits(:one).entry_date, locale: locale, format: :travel),
                        I18n.t('common.to', locale: locale),
                        I18n.l(visits(:one).exit_date, locale: locale, format: :travel)].join(' ')
          choice = find('button', text: countries(:Germany).localized_name(locale))
          assert_includes choice.text, date_range
          refute_includes choice.text, visits(:one).entry_date.iso8601
          choice.click
        end
        assert_selector '#visitModal.show', text: I18n.t('visits.edit_title', locale: locale), wait: 10
        assert_equal 'DE', find('#visit_country_code', visible: :all).value
        assert_equal visits(:one).entry_date.iso8601, find('#visit_entry_date').value
      ensure
        page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
        page.current_window.resize_to(1400, 1000)
      end
    end
  end

  test 'larger localized weekday labels keep the last calendar column reachable on mobile' do
    user_login
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride', width: 390, height: 844,
                                    deviceScaleFactor: 1, mobile: true)
    visit '/hi/my/days?year=2014&month=3&day=22'
    page.execute_script(<<~JS)
      document.querySelectorAll('#month-3 .day-header').forEach(function(header) {
        header.style.fontSize = '2rem';
      });
    JS
    assert_calendar_grid_fits
    find('[data-date="2014-03-22"]').click
    assert_selector '#calendar-visit-form button', count: 2
  ensure
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
    page.current_window.resize_to(1400, 1000)
  end

  test 'missing visa information before choosing a visit links directly to Add Visa' do
    people(:visa_required_person).visits.create!(country: countries(:Australia),
      entry_date: Date.new(2016, 3, 8), exit_date: Date.new(2016, 3, 9))
    visa_user_login
    visit '/en/my/days?year=2016&month=3&day=8'
    # A previous edit must not leave the later visit-choice summary hidden.
    find('[data-date="2016-03-02"]').click
    assert_selector '#visitModal.show form[data-visit-form]'
    within('#visitModal') { click_button 'Cancel' }
    assert_no_selector '.modal-backdrop'
    find('[data-date="2016-03-08"]').click
    assert_selector '#calendar-visit-form button', count: 2
    assert_selector '#calendar-day-info', text: I18n.t('days.tooltip.no_visa')
    assert_equal I18n.t('visits.add_visa'), find('[data-day-add-visa]').text
    find('[data-day-add-visa]').click
    assert_current_path private_visits_path(locale: :en), ignore_query: true
    assert_selector '#visaModal.show form', wait: 10
  end

  test 'a failed calendar refresh can be retried without repeating the saved edit' do
    user_login
    visit '/en/my/days?year=2014&month=3&day=10'
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-calendar-visit-form="true"]', wait: 10
    fill_in 'visit_exit_date', with: Date.iso8601('2014-03-21')
    # Fail this browser's refresh, including retries, until explicitly restored.
    # Queued requests from other tests cannot consume a one-shot server failure.
    page.driver.browser.execute_cdp('Network.enable')
    page.driver.browser.execute_cdp('Network.setBlockedURLs', urls: ['*/my/days.json*'])
    click_button I18n.t('common.save')
    assert_selector '#calendar-feedback', text: I18n.t('days.saved_refresh_error'), wait: 10
    assert_equal Date.new(2014, 3, 21), visits(:one).reload.exit_date
    page.driver.browser.execute_cdp('Network.setBlockedURLs', urls: [])
    assert_no_difference('Visit.count') do
      within('#calendar-feedback') { click_button I18n.t('days.retry') }
      assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
    end
  ensure
    page.driver.browser.execute_cdp('Network.setBlockedURLs', urls: [])
  end

  [390, 1400].each do |width|
    test "calendar edits at #{width}px keep the displayed year and scroll when a visit moves to another year" do
      page.current_window.resize_to(width, 844)
      user_login
      visit '/en/my/days?year=2014&month=3&day=10'
      cell = find('[data-date="2014-03-10"]')
      page.execute_script(<<~JS, cell)
        document.dispatchEvent(new Event('pointerdown'));
        arguments[0].scrollIntoView({ block: 'center', behavior: 'instant' });
        window.calendarDocumentMarker = 'original';
      JS
      initial_top = page.evaluate_script('arguments[0].getBoundingClientRect().top', cell)
      page.execute_script('arguments[0].click()', cell)
      assert_selector '#visitModal.show', text: I18n.t('visits.edit_title'), wait: 10
      assert_no_selector '#calendar-day-info'
      assert_selector '#entry-date-info', text: I18n.t('visits.entry_info')
      fill_in 'visit_entry_date', with: Date.iso8601('2015-03-10')
      fill_in 'visit_exit_date', with: Date.iso8601('2015-03-22')
      click_button I18n.t('common.save')
      assert_no_selector '#visitModal.show', wait: 10
      assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
      assert_selector '.calendar-view-container[data-selected-year="2014"]'
      assert_selector '.day-cell.no-travel[data-date="2014-03-10"]'
      assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
      assert_in_delta initial_top, page.evaluate_script('document.querySelector(\'[data-date="2014-03-10"]\').getBoundingClientRect().top'), 2
    ensure
      page.current_window.resize_to(1400, 1000)
    end
  end

  test 'public scripts work while injected inline scripts and handlers are blocked' do
    original_css = ApplicationHelper.instance_method(:critical_css)
    ApplicationHelper.define_method(:critical_css) do
      original_css.bind_call(self) + <<~HTML
        </style><script>window.cspInjected = true;</script>
        <button id="csp-injection-probe" onclick="window.cspInjected = true">CSP probe</button><style>
      HTML
    end
    visit '/en/about'
    assert_selector '.about-section'
    assert_equal 'function', page.evaluate_script('typeof window.jQuery')
    assert_equal false, page.evaluate_script('!!window.cspInjected')
    find('#csp-injection-probe').click
    assert_equal false, page.evaluate_script('!!window.cspInjected')
    assert_no_selector 'meta[name="csp-nonce"]', visible: :all
    original_url = page.current_url
    page.execute_script <<~JS
      var select = document.querySelector('.language-select');
      var option = select.options[select.selectedIndex];
      var originalValue = option.value;
      ['javascript:window.cspInjected=true', '//attacker.invalid/', '/\\\\attacker.invalid/'].forEach(function(value) {
        option.value = value;
        select.dispatchEvent(new Event('change', { bubbles: true }));
      });
      option.value = originalValue;
    JS
    assert_equal original_url, page.current_url
    assert_equal false, page.evaluate_script('!!window.cspInjected')
    find('.language-select', match: :first).select('FR - Français')
    assert_selector 'html[lang="fr"]', wait: 10
  ensure
    ApplicationHelper.define_method(:critical_css, original_css) if original_css
  end

  test 'private calculator modal scripts and form initialization work with a fresh nonce' do
    user_login
    nonce = find('meta[name="csp-nonce"]', visible: :all)['content']
    assert nonce.present?
    find('[data-action="add-visit"]', match: :first).click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]', wait: 10
    assert_no_selector '#visitModal script', visible: :all
    within '#visitModal' do
      choose_visit_country('India')
      fill_in 'visit_entry_date', with: Date.iso8601('2015-01-10')
      fill_in 'visit_exit_date', with: Date.iso8601('2015-01-12')
    end
    click_button I18n.t('common.save'), match: :first
    assert_no_selector '#visitModal.show', wait: 10
    assert_selector 'tr', text: 'India', wait: 10
  end

  test 'a cached public nationality form opens an uncached calculator without an inline handler' do
    visit '/en/visits'
    assert_no_selector 'meta[name="csp-nonce"]', visible: :all
    assert_no_difference('User.count') do
      find('#calculator_nationality_selector').select('India')
      assert_current_path private_visits_path(locale: :en), ignore_query: true, wait: 10
    end
    assert_selector 'meta[name="csp-nonce"]', visible: :all
    find('[data-action="add-visit"]', match: :first).click
    assert_selector '#visitModal.show form[data-visit-form-initialized="true"]', wait: 10
  end

  private

  def assert_calendar_grid_fits
    grid = page.evaluate_script(<<~JS)
      (function() {
        const grid = document.querySelector('#month-3 .calendar-grid');
        return { locale: document.documentElement.lang, viewport: innerWidth,
                 width: grid.clientWidth, content: grid.scrollWidth,
                 columns: getComputedStyle(grid).gridTemplateColumns };
      })()
    JS
    assert_operator grid.fetch('content'), :<=, grid.fetch('width') + 2, grid.inspect
  end

  def touch_tap(element)
    # Live search can replace options. Re-find before reading geometry; never
    # retry the touch itself or its assertions.
    rect = element.synchronize do
      page.evaluate_script('arguments[0].getBoundingClientRect().toJSON()', element)
    end
    point = { x: rect['left'] + rect['width'] / 2, y: rect['top'] + rect['height'] / 2 }
    page.driver.browser.execute_cdp('Input.dispatchTouchEvent', type: 'touchStart', touchPoints: [point])
    page.driver.browser.execute_cdp('Input.dispatchTouchEvent', type: 'touchEnd', touchPoints: [])
  end
end
