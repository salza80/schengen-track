# frozen_string_literal: true

# Configure OmniAuth to allow GET requests for mobile compatibility
# GET requests are standard for OAuth and work better on mobile browsers
# The OAuth 2.0 'state' parameter provides built-in CSRF protection
OmniAuth.config.allowed_request_methods = %i[get post]

# Silence the GET warning since we've consciously chosen to use GET for OAuth
# and are relying on OAuth 2.0's built-in state parameter for CSRF protection
OmniAuth.config.silence_get_warning = true
