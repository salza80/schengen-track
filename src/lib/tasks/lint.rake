# frozen_string_literal: true

desc 'Check translations and compile Sass with strict deprecation checks'
task lint: %w[i18n:check styles:check]
