# Cached public HTML uses asset integrity hashes, never reusable nonces.
# Private documents get a fresh nonce for the legacy Rails AJAX script responses.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.img_src :self, :https, :data
    policy.script_src :none
    policy.script_src_attr :none
    policy.style_src :self, :unsafe_inline, 'https://fonts.googleapis.com'
    policy.font_src :self, 'https://fonts.gstatic.com'
    policy.object_src :none
    policy.base_uri :none
    # Chrome checks form redirects; Facebook continues on its mobile host on Android.
    policy.form_action :self, 'https://www.facebook.com', 'https://m.facebook.com'
    policy.frame_ancestors :self
  end
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(32) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
