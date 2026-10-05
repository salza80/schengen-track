require 'test_helper'

class PublicHeaderBrowserTest < JavascriptIntegrationTest
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
    assert_selector :select, 'Select your country of citizenship', selected: 'United States of America'

    select 'Australia', from: 'Select your country of citizenship'
    assert_current_path '/en/about/Australian', ignore_query: true
    assert_selector :select, 'Select your country of citizenship', selected: 'Australia'
    assert_no_text 'Select another country'
  end

  test 'invalid calculation links show their alert on the public page' do
    visit '/calculations/invalid-token'
    assert_selector '#public-notices', text: 'Calculation link is invalid or has expired.'
  end

  test 'anonymous calculator navigation keeps the generic header' do
    visit '/en/about'
    assert_selector '#public-user-menu'
    assert_no_selector '#personDropdown'

    find("nav a[href='/en/visits']", match: :first).click
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
    action_group = find('.person-switcher .dropdown-menu > .d-none.d-md-block')
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
  end
end
