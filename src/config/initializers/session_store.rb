# Be sure to restart your server when you modify this file.

# Configure session cookies with proper SameSite and Secure attributes for CloudFront/HTTPS compatibility
# These settings are required for Rails 7+ to work correctly with modern browsers and CDN
Rails.application.config.session_store :cookie_store,
  key: '_schengen_track_session',
  same_site: :lax,    # Required for Chrome with CloudFront/HTTPS
  secure: Rails.env.production?, # Secure flag only in production
  httponly: true          # Security best practice
  # Note: Not setting domain explicitly - defaults to current host
