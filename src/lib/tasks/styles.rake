# frozen_string_literal: true

require_relative '../assets/sass_deprecations'

namespace :styles do
  desc 'Compile assets and fail on app Sass deprecations (local, opt-in check)'
  task check: :environment do
    logger = Assets::SassDeprecations.new(
      root: Rails.root, bootstrap_root: Gem.loaded_specs.fetch('bootstrap').full_gem_path
    )
    configuration = Rails.application.config.sass
    previous_logger, previous_verbose = configuration.logger, configuration.verbose

    begin
      configuration.logger = logger
      configuration.verbose = true
      # Fresh in-memory cache prevents a prior warning-only build from hiding
      # warnings, without writing precompiled files into the local site.
      environment = Sprockets::Railtie.build_environment(Rails.application)
      environment.cache = Sprockets::Cache::MemoryStore.new
      stylesheets = Rails.application.config.assets.precompile.flat_map do |path|
        environment.find_all_linked_assets(path).filter_map do |asset|
          asset.logical_path if asset.content_type == 'text/css'
        end
      end.uniq

      abort "Sass deprecations must be fixed:\n#{logger.violations.uniq.join("\n")}" if logger.violations.any?
      puts "✓ #{stylesheets.length} stylesheets checked; no app Sass deprecations."
      puts "  #{logger.compatibility_warnings} known Bootstrap compatibility warnings allowed."
    ensure
      configuration.logger = previous_logger
      configuration.verbose = previous_verbose
    end
  end
end
