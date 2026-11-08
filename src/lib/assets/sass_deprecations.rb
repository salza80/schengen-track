# frozen_string_literal: true

require 'uri'

module Assets
  # Opt-in logger for the local styles check. Normal builds keep Sass defaults.
  class SassDeprecations
    BOOTSTRAP_DEPRECATIONS = %w[import global-builtin color-functions if-function].freeze

    attr_reader :violations, :compatibility_warnings

    def initialize(root:, bootstrap_root:)
      @root = File.expand_path(root)
      @bootstrap_root = File.join(File.expand_path(bootstrap_root), 'assets/stylesheets/bootstrap/')
      @compatibility_file = File.join(@root, 'app/assets/stylesheets/_bootstrap_compat.scss')
      @violations = []
      @compatibility_warnings = 0
    end

    def warn(message, context)
      unless context.deprecation
        $stderr.puts(message)
        return
      end

      span = context.span
      url = span&.url
      filename = URI::DEFAULT_PARSER.unescape(URI.parse(url).path) if url&.start_with?('file:')
      type = context.deprecation_type
      bootstrap_warning = filename&.start_with?(@bootstrap_root) && BOOTSTRAP_DEPRECATIONS.include?(type)
      compatibility_import = filename == @compatibility_file && type == 'import' &&
        span.text.match?(/\A["'](?:theme|bootstrap\/[\w\/-]+)["']\z/)

      if bootstrap_warning || compatibility_import
        @compatibility_warnings += 1
      else
        location = filename ? filename.delete_prefix("#{@root}/") : (url || 'unknown source')
        line = span&.start&.line
        location += ":#{line + 1}" if line
        @violations << "#{location} [#{type}]: #{message}"
      end
    end
  end
end
