require 'test_helper'

class BlogsTest < ActionDispatch::IntegrationTest
  test 'blog link works' do
    visit blog_path(locale: :en, slug: 'extended-schengen-stay')

    assert has_content?('How to Stay in Europe Longer Than 90 Days'), "Should show new blog title"
    click_link 'Get started with the Schengen Calculator'
    assert has_content?('Travel Record')
  end

  test 'blog structured data renders as a JSON-LD object array' do
    get blog_path(locale: :en, slug: 'extended-schengen-stay')

    assert_response :success

    blog_schema_document = json_ld_documents.find do |document|
      document.is_a?(Array) && document.any? { |item| item['@type'] == 'BlogPosting' }
    end

    assert blog_schema_document, 'Expected BlogPosting JSON-LD to be rendered in an array'
    assert_equal 1, blog_schema_document.count { |item| item['@type'] == 'BlogPosting' }
  end

  private

  def json_ld_documents
    Nokogiri::HTML(response.body).css('script[type="application/ld+json"]').map do |script|
      JSON.parse(script.text)
    end
  end
end
