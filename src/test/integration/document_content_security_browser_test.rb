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
    page.execute_script('arguments[0].click()', cell)
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
    assert_equal '12', find('#visit_entry_date_3i').value
    assert page.evaluate_script(<<~JS)
      document.getElementById('calendar-day-info').getBoundingClientRect().top >=
        document.querySelector('#visitModal .modal-body').getBoundingClientRect().top
    JS
    select '14', from: 'visit_exit_date_3i'
    select 'Germany', from: 'visit_country_id'
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
    select '15', from: 'visit_exit_date_3i'
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
    select '9', from: 'visit_exit_date_3i'
    click_button I18n.t('common.save')
    assert_selector '#calendar-visit-form .alert-danger', wait: 10
    assert_selector '#calendar-day-info strong', text: 'Germany'
    assert_equal '9', find('#visit_exit_date_3i').value
    assert_equal 'DE', find('#visit_country_id').value
    assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
    # Arrow keys in a date select must not trigger the calendar's year navigation.
    page.execute_script("document.getElementById('visit_exit_date_3i').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }))")
    select '21', from: 'visit_exit_date_3i'
    click_button I18n.t('common.save')
    assert_no_selector '#visitModal.show', wait: 10
    assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
    assert_equal 'original', page.evaluate_script('window.calendarDocumentMarker')
  end

  test 'a border day offers its visits within the day information dialog' do
    user_login
    visit '/en/my/days?year=2014&month=3&day=22'
    find('[data-date="2014-03-22"]').click
    assert_selector '#visitModal.show #calendar-day-info'
    within '#calendar-visit-form' do
      assert_selector 'button', count: 2, wait: 10
      find('button', text: 'Germany').click
    end
    assert_selector '#visitModal.show', text: I18n.t('visits.edit_title'), wait: 10
    assert_equal 'DE', find('#visit_country_id').value
  end

  test 'a failed calendar refresh can be retried without repeating the saved edit' do
    original_index = DaysController.instance_method(:index)
    fail_next_refresh = true
    DaysController.define_method(:index) do
      if request.format.json? && fail_next_refresh
        fail_next_refresh = false
        render json: {}, status: :service_unavailable
      else
        original_index.bind_call(self)
      end
    end
    user_login
    visit '/en/my/days?year=2014&month=3&day=10'
    find('[data-date="2014-03-10"]').click
    assert_selector '#visitModal.show form[data-calendar-visit-form="true"]', wait: 10
    select '21', from: 'visit_exit_date_3i'
    click_button I18n.t('common.save')
    assert_selector '#calendar-feedback', text: I18n.t('days.refresh_error'), wait: 10
    assert_equal Date.new(2014, 3, 21), visits(:one).reload.exit_date
    assert_no_difference('Visit.count') do
      within('#calendar-feedback') { click_button I18n.t('days.retry') }
      assert_selector '#calendar-feedback', text: I18n.t('days.saved'), wait: 10
    end
  ensure
    DaysController.define_method(:index, original_index) if original_index
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
      assert_selector '#calendar-day-info strong', text: 'Germany'
      select '2015', from: 'visit_entry_date_1i'
      select '2015', from: 'visit_exit_date_1i'
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
    assert_selector '#visitModal [data-continent-selector]'
    within '#visitModal' do
      find('[data-continent-selector]').select('Asia')
      assert_selector '#visit_country_id option[value="IN"]', visible: :all
      find('#visit_country_id').select('India')
      find('#visit_entry_date_1i').select('2015')
      find('#visit_entry_date_2i').select('January')
      find('#visit_entry_date_3i').select('10')
      find('#visit_exit_date_1i').select('2015')
      find('#visit_exit_date_2i').select('January')
      find('#visit_exit_date_3i').select('12')
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
end
