# frozen_string_literal: true

module DocumentContentSecurityHelper
  def trusted_javascript_tag(name)
    integrity = asset_integrity(name, type: :javascript)
    raise "Missing asset integrity for #{name}" if integrity.blank?

    hashes = (request.env['schengen.trusted_script_integrities'] ||= [])
    hashes.concat(integrity.split).uniq!
    tag.script(src: asset_path("#{name}.js"), integrity: integrity, crossorigin: 'anonymous', defer: true)
  end
end
