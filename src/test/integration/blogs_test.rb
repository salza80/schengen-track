require 'test_helper'

class BlogsTest < ActionDispatch::IntegrationTest
  test 'blog link works' do
    visit blog_path('extended-schengen-stay')

    assert has_content? 'Travel Around Europe for More Than 90 Days'
    click_link 'Get started with the Schengen Calculator'
    assert has_content? 'Travel Record'
  end
end
