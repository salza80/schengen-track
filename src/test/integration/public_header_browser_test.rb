require 'test_helper'

class PublicHeaderBrowserTest < JavascriptIntegrationTest
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
