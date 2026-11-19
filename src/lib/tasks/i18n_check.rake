# frozen_string_literal: true

namespace :i18n do
  desc 'Check for missing, unused, and placeholder translations'
  task check: :environment do
    puts '========================================'
    puts 'i18n Translation Check (powered by i18n-tasks)'
    puts '========================================'
    puts

    # Run i18n-tasks health check
    system('bundle exec i18n-tasks health')
    exit_code = $?.exitstatus

    # Check for placeholders (i18n-tasks doesn't check for this by default)
    placeholders = find_placeholders
    total_placeholders = placeholders.values.flatten.length

    if total_placeholders.positive?
      puts
      puts "PLACEHOLDER TRANSLATIONS (#{total_placeholders})"
      puts '----------------------------'
      placeholders.each do |locale, keys|
        puts "#{locale_name(locale)} (#{locale}) - #{keys.length} placeholders:"
        keys.first(10).each do |key|
          puts "  #{key}"
        end
        puts "  ... and #{keys.length - 10} more" if keys.length > 10
        puts
      end
    end

    puts
    puts '========================================'
    puts 'Additional Commands:'
    puts "  rails i18n:add_placeholders  - Add placeholders for missing keys"
    puts "  rails i18n:remove_unused     - Remove unused keys"
    puts "  rails i18n:normalize         - Normalize and sort YAML files"
    puts '========================================'

    exit 1 if exit_code != 0 || total_placeholders.positive?
  end

  desc 'Add placeholder translations for missing keys'
  task add_placeholders: :environment do
    puts 'Adding placeholders for missing translations...'
    puts

    # Use i18n-tasks to add missing keys
    system('bundle exec i18n-tasks add-missing --value "[TRANSLATE] %{value}"')

    puts
    puts '✓ Placeholders added successfully'
    puts 'Search for [TRANSLATE] to find keys needing translation:'
    puts '  grep -rn "\[TRANSLATE\]" config/locales/'
  end

  desc 'Remove unused translation keys'
  task remove_unused: :environment do
    puts 'Finding unused translation keys...'
    puts

    # Show unused keys
    system('bundle exec i18n-tasks unused')

    puts
    puts '⚠ WARNING: This will remove unused keys from ALL locale files.'
    puts
    print 'Remove these keys? (y/N): '

    return unless $stdin.gets.chomp.downcase == 'y'

    puts
    puts 'Removing unused keys...'
    system('bundle exec i18n-tasks remove-unused')

    puts
    puts '✓ Unused keys removed successfully'
  end

  desc 'Normalize and sort YAML files'
  task normalize: :environment do
    puts 'Normalizing YAML files...'
    system('bundle exec i18n-tasks normalize')
    puts '✓ YAML files normalized successfully'
  end

  # Helper methods
  private

  def find_placeholders
    placeholders = {}
    locale_dir = Rails.root.join('config', 'locales')

    Dir.glob(File.join(locale_dir, '*.yml')).each do |file|
      content = File.read(file)
      next unless content.include?('[TRANSLATE]')

      # Parse YAML and find keys with [TRANSLATE]
      data = YAML.load_file(file)
      locale = File.basename(file, '.yml').split('.').last

      placeholder_keys = []
      flatten_hash(data).each do |key, value|
        placeholder_keys << key if value.to_s.include?('[TRANSLATE]')
      end

      placeholders[locale] = placeholder_keys unless placeholder_keys.empty?
    end

    placeholders
  end

  def flatten_hash(hash, parent_key = '', result = {})
    hash.each do |key, value|
      new_key = parent_key.empty? ? key.to_s : "#{parent_key}.#{key}"

      if value.is_a?(Hash)
        flatten_hash(value, new_key, result)
      else
        result[new_key] = value
      end
    end
    result
  end

  def locale_name(locale)
    names = {
      'en' => 'English',
      'de' => 'German',
      'es' => 'Spanish',
      'hi' => 'Hindi',
      'tr' => 'Turkish',
      'zh-CN' => 'Chinese'
    }
    names[locale] || locale
  end
end
