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
