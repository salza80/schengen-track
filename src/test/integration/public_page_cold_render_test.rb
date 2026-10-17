require 'test_helper'

class PublicPageColdRenderTest < ActionDispatch::IntegrationTest
  PUBLIC_HTML_SUFFIXES = [
    '',
    '/about',
    '/about/American',
    '/blog/extended-schengen-stay',
    '/disclaimer',
    '/privacy',
    '/datadeletion',
    '/visits',
    '/days?year=2027'
  ].freeze

  PUBLIC_DOCUMENT_PATHS = %w[
    /api/docs
    /openapi.json
    /robots.txt
    /llms.txt
    /llms-full.txt
    /sitemap.xml
    /ads.txt
  ].freeze

  test 'every public cacheable page renders without SQL on cold model metadata' do
    public_html_paths.each do |path|
      assert_cold_render_without_sql(path)
    end
  end

  test 'every public cacheable document is served without SQL' do
    PUBLIC_DOCUMENT_PATHS.each do |path|
      assert_cold_render_without_sql(path)
    end
  end

  private

  def public_html_paths
    locale_prefixes = [''] + I18n.available_locales.map { |locale| "/#{locale}" }

    locale_prefixes.product(PUBLIC_HTML_SUFFIXES).map do |prefix, suffix|
      path = "#{prefix}#{suffix}"
      path.empty? ? '/' : path
    end
  end

  def assert_cold_render_without_sql(path)
    reset!
    reset_model_metadata!
    CountryCatalog.reset!

    queries = capture_database_queries { get path }

    assert_response :success, "expected #{path} to render successfully"
    assert_empty queries, "expected #{path} to render without SQL, got:\n#{queries.join("\n")}"
  end

  def reset_model_metadata!
    Rails.application.eager_load!
    ApplicationRecord.descendants.reject(&:abstract_class?).each(&:reset_column_information)
  end
end
