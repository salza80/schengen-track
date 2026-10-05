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
    assert_selector '.step-summary', text: 'Choose your nationality'
    assert_selector '.step-summary', text: 'Save your trips'
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

  test 'guest can edit their own person after the public header loads' do
    visit '/en/about'
    assert_selector '#public-user-menu'
    assert_no_selector '#personDropdown'

    find("nav a[href='/en/visits']", match: :first).click
    assert_selector '#personDropdown', text: 'Guest User'
    find('#personDropdown').click
    edit_label = I18n.t('common.edit_current_person', locale: :en)
    own_edit_path = find_link(edit_label, match: :first)[:href]

    visit '/en/about'
    assert_selector '#public-user-menu #personDropdown', text: 'Guest User'
    find('#personDropdown').click
    assert_equal own_edit_path, find_link(edit_label, match: :first)[:href]
    click_link edit_label, match: :first
    assert_current_path own_edit_path
    assert_selector 'form'
  end
end
