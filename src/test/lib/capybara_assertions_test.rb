require 'test_helper'

class CapybaraAssertionsTest < JavascriptIntegrationTest
  test 'Capybara checks count as Minitest assertions' do
    node = Capybara.string('<button>Save visit</button>')
    previous_count = assertions

    assert_selector node, 'button', text: 'Save visit'
    assert_equal previous_count + 1, assertions

    assert_no_selector node, '.tooltip'
    assert_equal previous_count + 3, assertions
  end

  test 'failed Capybara checks are Minitest assertion failures' do
    node = Capybara.string('<button>Save visit</button>')

    assert_raises(Minitest::Assertion) { assert_selector node, '.missing', wait: 0 }
  end
end

class RailsSelectorAssertionsTest < ActionDispatch::IntegrationTest
  test 'Rails DOM selector assertions remain available in request tests' do
    document = Nokogiri::HTML.fragment('<form action="/visits"><input name="visit[entry_date]"></form>')

    assert_select document, 'form[action="/visits"]', count: 1
    assert_select document, 'input[name="visit[entry_date]"]', count: 1
  end
end
