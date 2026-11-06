class Users::PasswordsController < Devise::PasswordsController
  layout 'password_recovery'
  # Native forms on a no-referrer page send Origin: null in Chrome. Require
  # Rails' session-bound CSRF token while allowing that privacy-preserving form.
  self.forgery_protection_origin_check = false
  prepend_before_action :protect_recovery_response

  private

  def protect_recovery_response
    # Cover redirects and failed submissions as well as the token-bearing page.
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Content-Security-Policy'] = [
      "default-src 'none'", "style-src 'self'", "font-src 'self'",
      "img-src 'self'", "form-action 'self'", "base-uri 'none'",
      "frame-ancestors 'none'"
    ].join('; ')
  end
end
