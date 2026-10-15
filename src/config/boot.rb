ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

require_relative "../lib/database_url_loader"
DatabaseUrlLoader.load!
