require 'test_helper'

class PublicHeaderBrowserTest < JavascriptIntegrationTest
  test 'information alerts use the themed cool purple treatment' do
    user_login
    users(:Sally).people.where.not(id: people(:sally_person).id).destroy_all
    visit people_path(locale: :en)

    notice = find('.people-info-notice')
    icon = notice.find('.fa-info-circle')
    assert_equal 'rgba(232, 234, 246, 1)', notice.style('background-color')['background-color']
    assert_equal 'none', notice.style('background-image')['background-image']
    assert_equal 'rgba(197, 202, 233, 1)', notice.style('border-top-color')['border-top-color']
    assert_equal 'rgba(156, 39, 176, 1)', icon.style('color')['color']
  end

  test 'calendar uses one consistent summary until the desktop sidebar appears' do
    page.current_window.resize_to(900, 1000)
    user_login
    visit days_path(locale: :en, year: 2014)

    assert page.has_css?('.calendar-status-card', visible: true)
    assert page.has_css?('.calendar-status-card .status-metrics', visible: true)
    assert page.has_css?(".calendar-status-card a[href='#{visits_path(locale: :en)}']", visible: true)
    refute page.has_css?('.calendar-sidebar-col', visible: true)

    page.current_window.resize_to(700, 1000)
    assert page.has_css?('.calendar-status-card .status-metrics', visible: true)
    assert page.has_css?(".calendar-status-card a[href='#{visits_path(locale: :en)}']", visible: true)

    page.current_window.resize_to(1200, 1000)
    refute page.has_css?('.calendar-status-card', visible: true)
    assert page.has_css?('.calendar-sidebar-col', visible: true)
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'trips places status first while keeping supporting sidebar content at the bottom' do
    page.current_window.resize_to(900, 1000)
    user_login
    visit visits_path(locale: :en)

    assert page.has_css?('.calendar-status-card', visible: true)
    refute page.has_css?('.calendar-status-card a', visible: true)
    assert page.evaluate_script(<<~JS)
      document.querySelector('.calendar-status-card').compareDocumentPosition(
        document.querySelector('.section-heading')
      ) & Node.DOCUMENT_POSITION_FOLLOWING
    JS
    refute page.has_css?('.calendar-sidebar-status', visible: true)
    refute page.has_css?('.calendar-sidebar .legend-item', visible: true)
    assert page.has_css?(".calendar-sidebar a[href='https://www.buymeacoffee.com/smclean17d']", visible: true)
    assert page.has_css?(".calendar-sidebar a[href='#{about_path(locale: :en)}']", visible: true)

    page.current_window.resize_to(1200, 1000)
    refute page.has_css?('.calendar-status-card', visible: true)
    assert page.has_css?('.calendar-sidebar-status', visible: true)
    refute page.has_css?('.calendar-sidebar .legend-item', visible: true)
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'data deletion keeps semantic heading levels with one underlined page title' do
    visit '/en/datadeletion'

    title = find('h1.legal-page-title', text: 'Data Deletion Policy')
    subtitle = find('h2.legal-page-subheading', text: 'How to delete your data')
    assert_equal '3px', title.style('border-bottom-width')['border-bottom-width']
    assert_equal '0px', subtitle.style('border-bottom-width')['border-bottom-width']
  end

  test 'header keeps its concise brand and navigation visible at compact desktop widths' do
    page.current_window.resize_to(1400, 1000)
    visit '/en/about'
    assert_equal '19.2px', find('.site-title').style('font-size')['font-size']
    assert_equal '600', find('.site-title').style('font-weight')['font-weight']
    assert_equal '17.6px', find('#navbarContent .nav-tabs .nav-link', match: :first).style('font-size')['font-size']

    page.current_window.resize_to(720, 900)

    I18n.available_locales.each do |locale|
      visit "/#{locale}/about"

      assert_selector '.site-title', exact_text: I18n.t('common.schengen_calculator', locale: locale)
      assert_equal '16.25px', find('.site-title').style('font-size')['font-size']
      assert_equal '500', find('.site-title').style('font-weight')['font-weight']
      assert_selector '#navbarContent', visible: true
      assert_no_selector '.navbar-toggler', visible: true
      assert_selector '#navbarContent .nav-tabs .nav-link', count: 4, visible: true
      first_tab = find('#navbarContent .nav-tabs .nav-link', match: :first)
      assert_equal '13px', first_tab.style('font-size')['font-size']
      assert_operator page.evaluate_script('document.documentElement.scrollWidth'),
                      :<=, page.evaluate_script('window.innerWidth'),
                      "Expected the #{locale} header to fit at the expanded breakpoint"
    end

    page.current_window.resize_to(719, 900)
    assert_selector '.navbar-toggler', visible: true
    assert_no_selector '#navbarContent', visible: true
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'collapsed header aligns navigation, traveler actions, and legal links consistently' do
    page.current_window.resize_to(1400, 1000)
    user_login
    page.current_window.resize_to(680, 900)
    visit days_path(locale: :en, year: 2014)

    find('.navbar-toggler').click
    assert_selector '#navbarContent.show', visible: true

    aligned_items = [
      find('#navbarContent .nav-tabs .nav-link', match: :first),
      find('#personDropdown'),
      find(".header-mobile-only a[href='#{new_person_path(locale: :en)}']", visible: true),
      find('.legal-links-mobile a', match: :first)
    ]
    aligned_items.each do |item|
      assert_equal 'left', item.style('text-align')['text-align']
    end
    assert_no_selector '.header-mobile-only > small'

    selector_rect = find('#personDropdown').native.rect
    menu_rect = find('#personDropdown').find(:xpath, '..').native.rect
    assert_in_delta menu_rect.width, selector_rect.width, 1
    assert_equal '0px', find('.person-switcher').style('border-top-width')['border-top-width']
    assert_equal '1px', find('#navbarContent .nav-tabs').style('border-bottom-width')['border-bottom-width']
    assert_equal 'center', find('.header-auth-button', visible: true).style('justify-content')['justify-content']

    page.current_window.resize_to(720, 900)
    visit days_path(locale: :en, year: 2014)
    control_widths_before = page.evaluate_script(<<~JS)
      ({
        selector: document.querySelector('#personDropdown').getBoundingClientRect().width,
        auth: document.querySelector('.header-auth-button').getBoundingClientRect().width
      })
    JS
    assert_in_delta 104, control_widths_before['selector'], 0.1
    assert_equal 'center', find('#personDropdown .person-info').style('text-align')['text-align']
    page.execute_script(<<~JS)
      document.querySelector('#personDropdown .person-name').textContent =
        'Alexandria Catherine Montgomery-Worthington';
      document.querySelector('#personDropdown .person-nationality').textContent =
        'Bosnian and Herzegovinian';
    JS
    person_name_metrics = page.evaluate_script(<<~JS)
      (() => {
        const name = document.querySelector('#personDropdown .person-name');
        return {
          clientWidth: name.clientWidth,
          scrollWidth: name.scrollWidth,
          textOverflow: getComputedStyle(name).textOverflow
        };
      })()
    JS
    control_widths_after = page.evaluate_script(<<~JS)
      ({
        selector: document.querySelector('#personDropdown').getBoundingClientRect().width,
        auth: document.querySelector('.header-auth-button').getBoundingClientRect().width
      })
    JS
    assert_in_delta control_widths_before['selector'], control_widths_after['selector'], 0.1
    assert_in_delta control_widths_before['auth'], control_widths_after['auth'], 0.1
    assert_operator person_name_metrics['scrollWidth'], :>, person_name_metrics['clientWidth']
    assert_equal 'ellipsis', person_name_metrics['textOverflow']
    assert_operator page.evaluate_script('document.documentElement.scrollWidth'),
                    :<=, page.evaluate_script('window.innerWidth')

    find('#personDropdown').click
    dropdown_rect = find('.person-switcher .dropdown-menu.show').native.rect
    assert_operator dropdown_rect.x, :>=, 0
    assert_operator dropdown_rect.x + dropdown_rect.width,
                    :<=, page.evaluate_script('window.innerWidth')
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'how-to steps share FAQ panels and use blue step headings' do
    visit '/en/about'
    assert_selector '.how-to-item', count: 5
    assert_selector '.about-section > h3', text: 'Multiple People:'
    assert_no_selector '.how-to-section h3', text: 'Multiple People:'
    assert_selector '.how-to-item:nth-child(3) .step-description p', count: 3
    assert_selector '.step-title', text: 'Step 5: (optional)'
    panel_styles = ['background-color', 'border-inline-start-color', 'border-inline-start-width']
    assert_equal find('.faq-answer', match: :first).style(*panel_styles),
                 find('.step-description', match: :first).style(*panel_styles)
    assert_match(/\Argb(?:a)?\(52, 152, 219(?:, 1)?\)\z/,
                 find('.step-number', match: :first).style('color')['color'])
    assert_equal find('.step-summary', text: 'Keep your trips across devices').style('color'),
                 find('.step-optional').style('color')
    assert_selector '.step-summary', text: 'Choose your nationality'
    assert_selector '.step-summary', text: 'Keep your trips across devices'
    assert_equal find('.faq-question', match: :first).style('color', 'font-weight'),
                 find('.step-summary', match: :first).style('color', 'font-weight')

    page.current_window.resize_to(390, 844)
    visit '/ar/about'
    panel = find('.step-description', match: :first)
    assert_equal '3px', panel.style('border-right-width')['border-right-width']
    assert_equal '0px', panel.style('border-left-width')['border-left-width']
    assert_operator panel.native.rect.width, :<=, find('.how-to-section').native.rect.width
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'about matches the blog spacing below the header across screen sizes' do
    page.current_window.resize_to(700, 1000)

    visit '/en/about'
    about_gap = page.evaluate_script(<<~JS)
      document.querySelector('#intro').getBoundingClientRect().top -
        document.querySelector('.navbar').getBoundingClientRect().bottom
    JS

    visit '/en/blog'
    blog_gap = page.evaluate_script(<<~JS)
      document.querySelector('.article-title').getBoundingClientRect().top -
        document.querySelector('.navbar').getBoundingClientRect().bottom
    JS

    assert_in_delta 16, about_gap, 0.1
    assert_in_delta blog_gap, about_gap, 0.1

    page.current_window.resize_to(1400, 1000)

    visit '/en/about'
    desktop_about_gap = page.evaluate_script(<<~JS)
      document.querySelector('#intro').getBoundingClientRect().top -
        document.querySelector('.navbar').getBoundingClientRect().bottom
    JS

    visit '/en/blog'
    desktop_blog_gap = page.evaluate_script(<<~JS)
      document.querySelector('.article-title').getBoundingClientRect().top -
        document.querySelector('.navbar').getBoundingClientRect().bottom
    JS

    assert_in_delta 32, desktop_about_gap, 0.1
    assert_in_delta desktop_blog_gap, desktop_about_gap, 0.1

    visit '/en/datadeletion'
    assert_equal '0px', find('.about-section').style('padding-top')['padding-top']
    assert_no_selector '.about-page-section'
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'citizenship label and selector share a row when space allows and wrap on mobile' do
    page.current_window.resize_to(1800, 1000)
    visit '/en/about'
    row = find('.nationality-selector')
    label = row.find('label')
    select = row.find('select')
    heading = find('.about-section h4', match: :first)
    assert_equal heading.style('font-size', 'font-weight', 'color'), label.style('font-size', 'font-weight', 'color')
    assert_operator select.native.rect.x, :>, label.native.rect.x
    assert_operator (select.native.rect.y - label.native.rect.y).abs, :<, 20

    page.current_window.resize_to(390, 844)
    assert_operator select.native.rect.y, :>=, label.native.rect.y + label.native.rect.height
    assert_operator select.native.rect.width, :<=, row.native.rect.width
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'citizenship selection remains visible after navigating between nationality pages' do
    visit '/en/about'
    select 'United States of America', from: 'Select your country of citizenship'
    assert_current_path '/en/about/American', ignore_query: true
    assert_equal '/en/about/American', page.current_path
    assert_selector :select, 'Select your country of citizenship', selected: 'United States of America'

    select 'Australia', from: 'Select your country of citizenship'
    assert_current_path '/en/about/Australian', ignore_query: true
    assert_selector :select, 'Select your country of citizenship', selected: 'Australia'
    assert_no_text 'Select another country'
  end

  test 'invalid calculation links show their alert on the public page' do
    visit '/calculations/invalid-token'
    assert_selector '#public-notices', text: 'Calculation link is invalid or has expired.'
    assert_includes page.text, 'Calculation link is invalid or has expired.'
  end

  test 'anonymous calculator navigation keeps the generic header' do
    visit '/en/about'
    assert_selector '#public-user-menu'
    assert_no_selector '#personDropdown'

    find("nav a[href='/en/visits']", match: :first).click
    assert_equal '/en/visits', page.current_path
    assert_no_selector '#personDropdown'
    assert_selector 'h3.section-heading .fa-globe'
    assert_selector 'h3.section-heading', text: I18n.t('common.select_nationality', locale: :en)
    assert_selector 'select[name="nationality_id"]'
    assert_selector 'a', text: I18n.t('common.login', locale: :en)
    assert_selector "a.btn-add[href='/en/visits?open=trip']", text: I18n.t('visits.add_travel', locale: :en)

    visit '/en/about'
    assert_selector '#public-user-menu'
    assert_no_selector '#personDropdown'
  end

  test 'first trip save replaces anonymous nationality selector with person menu' do
    visit '/en/visits'
    select 'India', from: 'calculator_nationality_selector'
    assert_selector 'select[name="nationality_id"] option[selected]', text: 'India'

    find('[data-action="add-visit"]', match: :first).click
    assert_selector '#visitModal.show', text: I18n.t('visits.add_record', locale: :en)
    assert_no_selector '#visitModal .nationality-step-form'
    select '2027', from: 'visit_entry_date_1i'
    select 'January', from: 'visit_entry_date_2i'
    select '10', from: 'visit_entry_date_3i'
    select '2027', from: 'visit_exit_date_1i'
    select 'January', from: 'visit_exit_date_2i'
    select '15', from: 'visit_exit_date_3i'
    select 'Germany', from: 'visit_country_id'
    find('#saveVisitButton').click

    assert_selector '#personDropdown', text: 'Guest User', wait: 10
    assert_equal 'Guest User', find('#personDropdown .person-name').text
    assert_no_selector 'select[name="nationality_id"]'
  end

  test 'add trip asks for nationality first when no preference was selected' do
    starting_users = User.count
    starting_people = Person.count

    visit '/en/about'
    within 'nav.navbar', match: :first do
      click_link I18n.t('visits.add_travel', locale: :en)
    end
    assert_selector '#visitModal.show', text: 'Choose your nationality'
    within '#visitModal' do
      select 'India', from: 'calculator_nationality_step'
      click_button I18n.t('common.continue', locale: :en)
    end

    assert_selector '#visitModal.show', text: I18n.t('visits.add_record', locale: :en), wait: 10
    assert_no_selector '#visitModal .nationality-step-form'
    assert_equal starting_users, User.count
    assert_equal starting_people, Person.count

    within '#visitModal' do
      click_button I18n.t('common.cancel', locale: :en)
    end
    assert_equal starting_users, User.count
    assert_equal starting_people, Person.count
  end

  test 'fresh Trips page Add Travel button opens the nationality step' do
    visit '/en/visits'

    add_travel_button = find('.empty-state [data-action="add-visit"]', match: :first)
    add_travel_button.click

    assert_selector '#visitModal.show', text: I18n.t('common.choose_nationality', locale: :en)
    assert_selector '#visitModal .nationality-step-form'
    assert_no_selector '#visitModal form[id^="new_visit"]'

    within '#visitModal' do
      find('button.close').click
    end

    assert_no_selector '#visitModal.show'
    assert_selector '.empty-state [data-action="add-visit"]:focus'
    assert_equal add_travel_button, page.active_element
  end

  test 'person selector closes when a calendar control handles an outside click' do
    user_login
    visit days_path(locale: :en, year: 2014)

    find('#personDropdown').click
    assert_selector '.person-switcher.show .dropdown-menu.show'
    action_group = find('.person-switcher .dropdown-menu > .header-desktop-only')
    menu_children = action_group.all(:xpath, './*', visible: :all)
    add_index = menu_children.index { |item| item[:href].to_s.end_with?(new_person_path(locale: :en)) }
    edit_index = menu_children.index { |item| item[:href].to_s.match?(%r{/en/people/\d+/edit\z}) }
    manage_index = menu_children.index { |item| item[:href].to_s.end_with?(people_path(locale: :en)) }
    assert_equal add_index + 1, edit_index
    assert_includes menu_children[edit_index + 1][:class].split, 'dropdown-divider'
    assert_equal edit_index + 2, manage_index

    first('.day-cell').click
    assert_no_selector '.person-switcher.show .dropdown-menu.show'
  end

  test 'logout matches outlined actions and the person selector height' do
    user_login
    visit visits_path(locale: :en)

    logout = find('a', text: I18n.t('common.log_out', locale: :en), exact_text: true)
    export = find('a', text: I18n.t('visits.export_to_csv', locale: :en), exact_text: true)
    person_selector = find('#personDropdown')

    assert_equal export.style('background-color', 'border-top-color'),
                 logout.style('background-color', 'border-top-color')
    assert_operator (logout.native.rect.height - person_selector.native.rect.height).abs, :<=, 2
  end

  test 'record tables use themed headers and unstriped white rows' do
    visa_user_login
    visit visits_path(locale: :en)

    status_blue = find('.calendar-sidebar .card-header.bg-primary', match: :first).style('background-color')
    table_headers = all('.bg-table-header th', minimum: 2)

    table_headers.each do |header|
      assert_equal status_blue, header.style('background-color')
    end

    tables = all('table.responsive-table', count: 2)
    tables.each do |table|
      refute_includes table[:class].split, 'table-striped'
    end

    all('table.responsive-table tbody tr', minimum: 2).each do |row|
      assert_equal 'rgba(255, 255, 255, 1)', row.style('background-color')['background-color']
    end

    visit people_path(locale: :en)

    people_table = find('table.responsive-table')
    people_header_blue = find('.bg-table-header th', match: :first).style('background-color')
    status_blue = find('.calendar-sidebar .card-header.bg-primary', match: :first).style('background-color')
    assert_equal status_blue, people_header_blue
    refute_includes people_table[:class].split, 'table-striped'
    assert_no_selector 'table.responsive-table tbody tr.table-active'
    all('table.responsive-table tbody tr', minimum: 1).each do |row|
      assert_equal 'rgba(255, 255, 255, 1)', row.style('background-color')['background-color']
    end
    all('.people-status-badge', minimum: 2).each do |badge|
      assert_equal '12.8px', badge.style('font-size')['font-size']
      assert_operator badge.native.rect.height, :>=, 22
    end

    page.current_window.resize_to(700, 1000)
    mobile_header = find('table.responsive-table tbody .bg-md-header', match: :first)
    assert_equal status_blue['background-color'], mobile_header.style('background-color')['background-color']
    assert_equal 'rgba(255, 255, 255, 1)', mobile_header.style('color')['color']
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test 'calendar day loads the shared visit modal behavior' do
    user_login
    visit days_path(locale: :en, year: 2030)

    day = first('.day-cell.no-travel')
    day.click

    assert_selector '#visitModal.show form[id^="new_visit"]', wait: 10
    within '#visitModal' do
      find('button.close').click
    end
    assert_no_selector '#visitModal.show'
    assert_selector '.day-cell:focus'
    assert_equal day, page.active_element
  end

  test 'people and account pages use the shared delete modal behavior' do
    user_login
    visit people_path(locale: :en)

    person_delete = first('.delete-person-link')
    person_delete.click
    assert_selector '#deleteModal.show'
    within '#deleteModal' do
      click_button I18n.t('common.cancel', locale: :en)
    end
    assert_selector '.delete-person-link:focus'
    assert_equal person_delete, page.active_element

    visit my_details_path(locale: :en)
    account_delete = find('#deleteAccountButton')
    account_delete.click
    assert_selector '#deleteModal.show'
    within '#deleteModal' do
      click_button I18n.t('common.cancel', locale: :en)
    end
    assert_selector '#deleteAccountButton:focus'
    assert_equal account_delete, page.active_element
  end

  test 'trip delete modal restores focus to its trigger' do
    user_login
    visit visits_path(locale: :en)

    delete_link = first('.delete-visit-link')
    delete_link.click
    assert_selector '#deleteModal.show'
    within '#deleteModal' do
      click_button I18n.t('common.cancel', locale: :en)
    end

    assert_no_selector '#deleteModal.show'
    assert_selector '.delete-visit-link:focus'
    assert_equal delete_link, page.active_element
  end

  test 'invalid visa remains in the shared modal with validation errors' do
    visa_user_login
    visit visits_path(locale: :en)

    find('[data-action="add-visa"]', match: :first).click
    assert_selector '#visaModal.show form[id^="new_visa"]'

    within '#visaModal' do
      select '2027', from: 'visa_start_date_1i'
      select 'December', from: 'visa_start_date_2i'
      select '31', from: 'visa_start_date_3i'
      select '2027', from: 'visa_end_date_1i'
      select 'January', from: 'visa_end_date_2i'
      select '1', from: 'visa_end_date_3i'
      fill_in 'visa_no_entries', with: '1'
      find('#saveVisaButton').click
    end

    assert_selector '#visaModal.show .alert-danger', wait: 10
    assert find('#visaModal .alert-danger').visible?
  end
end
