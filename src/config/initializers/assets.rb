# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )

# Precompile split JavaScript bundles for code splitting optimization
# - core.js: Core libraries (jQuery, Bootstrap) loaded on all pages
# - calendar_bundle.js: Calendar-specific code for days#index
# - visits_bundle.js: Visits management for visits#index
Rails.application.config.assets.precompile += %w( core.js calendar_bundle.js visits_bundle.js )
