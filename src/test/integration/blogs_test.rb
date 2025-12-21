require 'test_helper'

class BlogsTest < ActionDispatch::IntegrationTest
  test 'blog link works' do
    visit blog_path(locale: :en, slug: 'extended-schengen-stay')

    assert has_content?('How to Stay in Europe Longer Than 90 Days'), "Should show new blog title"
    click_link 'Get started with the Schengen Calculator'
    assert has_content?('Travel Record')
  end
end
