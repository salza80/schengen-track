require 'test_helper'
require 'sass-embedded'
require 'tmpdir'
require Rails.root.join('lib/assets/sass_deprecations')

class SassDeprecationsTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir('sass deprecations-')
    @root = File.join(@directory, 'app')
    @bootstrap_root = File.join(@directory, 'bootstrap')
    @stylesheets = File.join(@root, 'app/assets/stylesheets')
    @logger = Assets::SassDeprecations.new(root: @root, bootstrap_root: @bootstrap_root)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_modern_app_styles_have_no_deprecations
    css = compile('@use "sass:color"; a { color: color.adjust(#2196f3, $lightness: -10%); }')

    assert_includes css, 'color:'
    assert_empty @logger.violations
    assert_equal 0, @logger.compatibility_warnings
  end

  def test_app_color_functions_are_reported_with_the_decoded_source_location
    compile('a { color: darken(#2196f3, 10%); }')

    assert_equal 2, @logger.violations.length
    assert @logger.violations.all? { |message| message.start_with?('app/assets/stylesheets/probe.scss:1 ') }
    assert @logger.violations.any? { |message| message.include?('[color-functions]') }
    assert @logger.violations.any? { |message| message.include?('[global-builtin]') }
  end

  def test_known_bootstrap_color_warnings_are_allowed_only_inside_its_sass_directory
    compile('a { color: darken(#2196f3, 10%); }',
            filename: File.join(@bootstrap_root, 'assets/stylesheets/bootstrap/_functions.scss'))

    assert_empty @logger.violations
    assert_equal 2, @logger.compatibility_warnings

    compile('a { color: darken(#2196f3, 10%); }',
            filename: File.join(@bootstrap_root, 'assets/stylesheets/bootstrap-other.scss'))
    assert_equal 2, @logger.violations.length
  end

  def test_only_the_bridge_can_import_theme_and_bootstrap
    write_stylesheet(File.join(@stylesheets, '_theme.scss'), '$primary: blue;')
    bridge = File.join(@stylesheets, '_bootstrap_compat.scss')
    compile('@import "theme";', filename: bridge)
    assert_empty @logger.violations
    assert_equal 1, @logger.compatibility_warnings

    compile('@import "theme";')
    assert_equal 1, @logger.violations.length
    assert_includes @logger.violations.first, '[import]'
  end

  def test_the_bridge_cannot_hide_other_app_imports_or_deprecated_functions
    write_stylesheet(File.join(@stylesheets, '_component.scss'), 'a { color: blue; }')
    compile('@import "component"; a { color: darken(blue, 10%); }',
            filename: File.join(@stylesheets, '_bootstrap_compat.scss'))

    assert_equal 3, @logger.violations.length
    assert_equal 0, @logger.compatibility_warnings
  end

  def test_new_bootstrap_deprecation_types_and_unknown_sources_are_not_exempt
    location = Struct.new(:line).new(0)
    span = Struct.new(:url, :start, :text).new(
      file_url(File.join(@bootstrap_root, 'assets/stylesheets/bootstrap/_functions.scss')), location, 'new syntax'
    )
    context = Struct.new(:deprecation, :deprecation_type, :span)
    @logger.warn('New upstream deprecation', context.new(true, 'future-deprecation', span))
    @logger.warn('Unknown origin', context.new(true, 'global-builtin', nil))

    assert_equal 2, @logger.violations.length
    assert_includes @logger.violations.last, 'unknown source'
  end

  def test_regular_sass_warnings_remain_visible_without_becoming_deprecation_errors
    _, stderr = capture_io { compile('@warn "Regular warning"; a { color: blue; }') }

    assert_includes stderr, 'Regular warning'
    assert_empty @logger.violations
  end

  def test_syntax_errors_remain_fatal_with_and_without_the_strict_logger
    [nil, @logger].each do |logger|
      assert_raises(Sass::CompileError) { Sass.compile_string('a { color: ;', logger: logger) }
    end
  end

  private

  def compile(source, filename: File.join(@stylesheets, 'probe.scss'))
    write_stylesheet(filename, source)
    Sass.compile(filename, logger: @logger, verbose: true, load_paths: [@stylesheets]).css
  end

  def write_stylesheet(filename, source)
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, source)
  end

  def file_url(filename)
    "file://#{URI::DEFAULT_PARSER.escape(filename)}"
  end
end
