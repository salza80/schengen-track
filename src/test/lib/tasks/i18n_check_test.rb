require 'test_helper'
require 'minitest/mock'
require 'rake'
require 'tmpdir'
require 'open3'
require 'stringio'

class I18nCheckTaskTest < Minitest::Test
  def setup
    @previous_rake = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/i18n_check.rake')
    @previous_git_environment = ENV.to_h.slice('GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM')
    ENV['GIT_CONFIG_GLOBAL'] = File::NULL
    ENV['GIT_CONFIG_NOSYSTEM'] = '1'
    @directory = Pathname.new(Dir.mktmpdir('local checks '))
    @repository = @directory.join('repository')
    FileUtils.mkdir_p(@repository.join('src/bin'))
    git('init', '--quiet')
    @hook = @repository.join('.git/hooks/pre-commit')
  end

  def teardown
    Rake.application = @previous_rake
    %w[GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM].each do |key|
      @previous_git_environment.key?(key) ? ENV[key] = @previous_git_environment[key] : ENV.delete(key)
    end
    FileUtils.remove_entry(@directory)
  end

  def test_installs_an_executable_hook_in_a_checkout_with_spaces
    install_hook

    assert File.executable?(@hook)
    assert_includes @hook.read, 'bin/rails i18n:check'
    assert_includes @hook.read, 'bin/rails styles:check'
  end

  def test_worktrees_install_into_the_shared_git_hook_directory
    git('-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
        '-c', 'user.name=Hook Test', '-c', 'user.email=hook@example.com',
        'commit', '--allow-empty', '--quiet', '-m', 'Fixture')
    worktree = @directory.join('worktree')
    git('worktree', 'add', '--quiet', '--detach', worktree.to_s)

    install_hook(repository: worktree)

    assert File.executable?(@hook)
    assert worktree.join('.git').file?
  end

  def test_respects_the_configured_hook_path_and_creates_its_directory
    git('config', 'core.hooksPath', 'custom hooks')
    configured_hook = @repository.join('custom hooks/pre-commit')

    install_hook

    assert File.executable?(configured_hook)
    refute @hook.exist?
  end

  def test_declining_an_overwrite_preserves_the_existing_hook
    @hook.write('existing hook')

    install_hook(answer: "n\n")

    assert_equal 'existing hook', @hook.read
  end

  def test_end_of_input_preserves_the_existing_hook
    @hook.write('existing hook')

    install_hook

    assert_equal 'existing hook', @hook.read
  end

  def test_an_explicit_yes_updates_the_existing_hook
    @hook.write('existing hook')

    install_hook(answer: " Y \n")

    assert File.executable?(@hook)
    assert_includes @hook.read, 'bin/rails styles:check'
  end

  def test_local_hook_runs_translation_then_styles_checks
    status, calls = run_hook

    assert status.success?
    assert_equal %w[i18n:check styles:check], calls
  end

  def test_ci_hook_keeps_deprecations_nonblocking
    status, calls = run_hook(ci: 'true')

    assert status.success?
    assert_equal ['i18n:check'], calls
  end

  def test_failed_translations_block_the_commit_before_styles_run
    status, calls = run_hook(failing_check: 'i18n:check')

    assert_equal 7, status.exitstatus
    assert_equal ['i18n:check'], calls
  end

  def test_failed_styles_block_the_commit
    status, calls = run_hook(failing_check: 'styles:check')

    assert_equal 7, status.exitstatus
    assert_equal %w[i18n:check styles:check], calls
  end

  def test_installing_outside_a_git_repository_fails_clearly
    other_directory = @directory.join('not a repository')
    FileUtils.mkdir_p(other_directory)

    error = assert_raises(SystemExit) { install_hook(repository: other_directory) }

    refute_equal 0, error.status
    assert_match(/Cannot locate the Git pre-commit hook/, error.message)
  end

  private

  def git(*arguments)
    _, stderr, status = Open3.capture3('git', '-C', @repository.to_s, *arguments)
    assert status.success?, stderr
  end

  def install_hook(repository: @repository, answer: '')
    previous_stdin = $stdin
    $stdin = StringIO.new(answer)
    Rails.stub(:root, repository.join('src')) do
      capture_io { Rake::Task['i18n:install_hook'].invoke }
    end
  ensure
    $stdin = previous_stdin
  end

  def run_hook(ci: nil, failing_check: nil)
    install_hook
    rails = @repository.join('src/bin/rails')
    rails.write(<<~'SH')
      #!/bin/bash
      echo "$*" >> ../check-calls
      if [ "$1" = "${FAILING_LOCAL_CHECK:-}" ]; then exit 7; fi
    SH
    rails.chmod(0o755)
    _, _, status = Open3.capture3(
      { 'CI' => ci, 'FAILING_LOCAL_CHECK' => failing_check }, @hook.to_s, chdir: @repository.to_s
    )
    [status, @repository.join('check-calls').read.lines.map(&:chomp)]
  end
end
