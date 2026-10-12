# frozen_string_literal: true

# Initiate OAuth through a real POST form. This keeps navigation in the current
# tab, works without JavaScript, and retains OmniAuth's request-phase CSRF guard.
OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.request_validation_phase = OmniAuth::AuthenticityTokenProtection.new(key: :_csrf_token)
