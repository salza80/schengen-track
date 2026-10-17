require 'test_helper'

class ApiDocsCacheTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'API documentation is publicly cacheable without SQL or session cookies' do
    queries = capture_database_queries { get '/api/docs' }

    assert_response :success
    assert_equal %w[max-age=0 public s-maxage=2592000], response.headers['Cache-Control'].split(', ').sort
    assert_nil response.headers['Set-Cookie']
    assert_empty queries
    assert_equal 'Schengen Calculator API', response.parsed_body['name']
  end

  test 'API documentation stays public and identical for signed-in visitors' do
    get '/api/docs'
    anonymous_body = response.body
    sign_in users(:Sally)
    # Devise's helper performs sign-in on the next request. Establish the
    # browser session before measuring the session-free documentation request.
    get my_details_path(locale: :en)
    assert_response :success

    queries = capture_database_queries { get '/api/docs' }

    assert_response :success
    assert_equal anonymous_body, response.body
    assert_equal %w[max-age=0 public s-maxage=2592000], response.headers['Cache-Control'].split(', ').sort
    assert_nil response.headers['Set-Cookie']
    assert_empty queries
  end
end
