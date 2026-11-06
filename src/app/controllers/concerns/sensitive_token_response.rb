module SensitiveTokenResponse
  extend ActiveSupport::Concern

  included do
    layout 'sensitive_token'
    # Chrome sends Origin: null from no-referrer forms. The session-bound
    # authenticity token remains mandatory on every state-changing request.
    self.forgery_protection_origin_check = false
    prepend_before_action :protect_sensitive_token_response
  end

  private

  def protect_sensitive_token_response
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Content-Security-Policy'] = [
      "default-src 'none'", "style-src 'self'", "font-src 'self'",
      "img-src 'self'", "form-action 'self'", "base-uri 'none'",
      "frame-ancestors 'none'"
    ].join('; ')
  end
end
