require 'test_helper'
require 'digest'
require 'base64'

class DocumentContentSecurityTest < ActionDispatch::IntegrationTest
  test 'cached public documents authorize the exact entrypoint bytes without nonces or inline handlers' do
    ['/en/about', '/en/blog/extended-schengen-stay', '/fr/visits', '/ar/days'].each do |path|
      get path
      assert_response :success
      policy = response.headers.fetch('Content-Security-Policy')
      assert_includes policy, "'strict-dynamic'"
      assert_includes policy, "script-src-attr 'none'"
      assert_includes policy, "object-src 'none'"
      script_policy = policy.split(';').find { |directive| directive.strip.start_with?('script-src ') }
      refute_includes script_policy, "'unsafe-inline'"
      refute_includes policy, "'nonce-"
      assert_select 'meta[name="csp-nonce"], [nonce], [onclick], [onchange], [onload]', count: 0
      assert_select 'script:not([src]):not([type="application/ld+json"])', count: 0
      entrypoints = css_select('script[src]').map { |script| [script['src'], script['integrity']] }
      assert entrypoints.any?
      entrypoints.each do |src, integrity|
        assert integrity.present?
        integrity.split.each { |hash| assert_includes script_policy, "'#{hash}'" }
        get src
        assert_response :success
        actual = "sha256-#{Base64.strict_encode64(Digest::SHA256.digest(response.body))}"
        assert_includes integrity.split, actual
      end
    end
  end

  test 'private documents use a different nonce on each response' do
    nonces = 2.times.map do
      get '/en/users/sign_in'
      assert_response :success
      nonce = css_select('meta[name="csp-nonce"]').first['content']
      assert_match(/\A[A-Za-z0-9+\/]{43}=\z/, nonce)
      assert_includes response.headers.fetch('Content-Security-Policy'), "'nonce-#{nonce}'"
      assert_includes response.headers.fetch('Content-Security-Policy'), "form-action 'self' https://www.facebook.com"
      nonce
    end
    refute_equal(*nonces)
  end

  test 'recovery keeps its stronger policy and has no third party scripts' do
    get '/en/users/password/new'
    assert_response :success
    policy = response.headers.fetch('Content-Security-Policy')
    assert_includes policy, "default-src 'none'"
    refute_includes policy, 'unsafe-eval'
    refute_includes policy, 'strict-dynamic'
    assert_select 'script, meta[name="csp-nonce"]', count: 0
  end
end
