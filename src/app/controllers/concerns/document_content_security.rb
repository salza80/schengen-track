# frozen_string_literal: true

module DocumentContentSecurity
  extend ActiveSupport::Concern

  included do
    after_action :set_document_content_security
  end

  private

  def set_document_content_security
    # Sensitive-token controllers supply a stronger, script-free policy.
    return if response.headers['Content-Security-Policy'].present?

    request.content_security_policy_nonce_generator = nil if @public_static_page
    policy = request.content_security_policy.clone
    hashes = Array(request.env['schengen.trusted_script_integrities']).map { |hash| "'#{hash}'" }
    # AdSense requires eval; strict-dynamic limits script elements to the
    # fingerprinted entrypoints and scripts they load. Inline handlers stay off.
    policy.script_src "'strict-dynamic'", "'unsafe-eval'", *hashes
    request.content_security_policy = policy
  end
end
