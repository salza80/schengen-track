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
    @directory = Pathname.new(Dir.mktmpdir('local checks '))
    @repository = @directory.join('repository')
    @calls = @directory.join('calls')
    @hook = @repository.join('.git/hooks/pre-commit')
    @previous_git_environment = ENV.to_h.slice('GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM')
    ENV['GIT_CONFIG_GLOBAL'] = @directory.join('global.gitconfig').to_s
    ENV['GIT_CONFIG_NOSYSTEM'] = '1'
    FileUtils.mkdir_p(@repository.join('src/bin'))
    git('init', '--quiet')
    git('config', 'user.name', 'Hook Test')
    git('config', 'user.email', 'hook@example.com')
    FileUtils.cp(Rails.root.join('bin/check-staged'), @repository.join('src/bin'))
    @repository.join('src/Gemfile').write('')
    @source = @repository.join('src/style.scss')
    @source.write('valid')
    rails = @repository.join('src/bin/rails')
    rails.write(<<~'SH')
      #!/bin/sh
      for task in "$@"; do
        echo "$task" >> "$CHECK_CALLS"
        if [ "$task" = "$FAILING_CHECK" ]; then exit 7; fi
        if [ "$task" = styles:check ] && [ "$(cat style.scss)" = deprecated ]; then exit 8; fi
      done
    SH
    rails.chmod(0o755)
    git('add', '.')
  end

  def teardown
    Rake.application = @previous_rake
    %w[GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM].each do |key|
      @previous_git_environment.key?(key) ? ENV[key] = @previous_git_environment[key] : ENV.delete(key)
    end
    FileUtils.remove_entry(@directory)
  end

  def test_worktrees_run_the_checks_against_their_own_index
    git('commit', '--quiet', '-m', 'Fixture')
    other = @directory.join('worktree')
    git('worktree', 'add', '--quiet', '--detach', other.to_s)
    install_hook(repository: other)

    other.join('src/style.scss').write('deprecated')
    git('add', 'src/style.scss', repository: other)
    assert_equal 8, run_hook(repository: other).exitstatus, @hook_output
    assert run_hook.success?
  end

  def test_repo_relative_custom_hook_path_with_spaces
    git('config', 'core.hooksPath', 'custom hooks')
    install_hook

    assert @repository.join('custom hooks/pre-commit').executable?
    assert run_hook.success?
    refute @hook.exist?
  end

  def test_global_hook_directory_is_preserved_for_both_repositories
    shared = @directory.join('shared hooks')
    shared.mkpath
    shared_hook = shared.join('pre-commit')
    content = "#!/bin/sh\necho shared >> \"$CHECK_CALLS\"\n"
    shared_hook.write(content)
    shared_hook.chmod(0o755)
    git('config', '--global', 'core.hooksPath', shared.to_s)

    if !configurable_hooks?
      assert_raises(SystemExit) { install_hook(answer: "y\n") }
      assert_equal content, shared_hook.read
      return
    end
    install_hook(answer: "y\n")
    assert run_hook.success?
    assert_equal %w[i18n:check shared styles:check], calls.sort
    assert_equal content, shared_hook.read

    other = @directory.join('unrelated')
    other.mkpath
    git('init', '--quiet', repository: other)
    @calls.unlink
    assert run_hook(repository: other).success?
    assert_equal ['shared'], calls
  end

  def test_symlinked_hooks_directory_is_never_written_through
    shared = @directory.join('shared')
    shared.mkpath
    File.symlink(shared, @repository.join('linked-hooks'))
    git('config', 'core.hooksPath', 'linked-hooks')
    if configurable_hooks?
      install_hook
      assert run_hook.success?
      assert_equal %w[i18n:check styles:check], calls
    else
      assert_raises(SystemExit) { install_hook }
    end
    assert_empty shared.children
  end

  def test_reinstall_after_changing_hook_paths_runs_the_project_checks_once
    skip 'Git lacks configurable hooks' unless configurable_hooks?
    install_hook
    git('config', 'core.hooksPath', @directory.join('shared').to_s)
    install_hook
    git('config', '--unset', 'core.hooksPath')
    # Worktrees can switch back to the old hook file before anyone reinstalls.
    assert run_hook.success?, @hook_output
    assert_equal %w[i18n:check styles:check], calls
    @calls.unlink
    2.times { install_hook }

    git('commit', '--quiet', '-m', 'Check once')
    assert_equal %w[i18n:check styles:check], calls
  end

  def test_switching_from_a_shared_path_preserves_an_unrelated_private_hook
    skip 'Git lacks configurable hooks' unless configurable_hooks?
    git('config', 'core.hooksPath', @directory.join('shared').to_s)
    install_hook
    git('config', '--unset', 'core.hooksPath')
    @hook.dirname.mkpath
    script = "#!/bin/sh\necho custom >> \"$CHECK_CALLS\"\n"
    @hook.write(script)
    @hook.chmod(0o755)
    install_hook(answer: "y\n")

    git('commit', '--quiet', '-m', 'Keep custom hook')
    assert_equal %w[custom i18n:check styles:check], calls.sort
    assert_equal script, @hook.read
  end

  def test_an_existing_hook_is_only_replaced_on_explicit_confirmation
    @hook.dirname.mkpath
    @hook.write('existing hook')
    ['', "n\n"].each do |answer|
      install_hook(answer: answer)
      assert_equal 'existing hook', @hook.read
    end
    install_hook(answer: " Y \n")
    assert @hook.executable?
    assert run_hook.success?
    assert_equal %w[i18n:check styles:check], calls
  end

  def test_local_hook_checks_the_index_even_when_the_working_copy_is_valid
    @source.write('deprecated')
    git('add', 'src/style.scss')
    @source.write('valid')
    install_hook

    assert_equal 8, run_hook.exitstatus
    assert_equal %w[i18n:check styles:check], calls
    assert_equal 'valid', @source.read
    assert_equal 'deprecated', git('show', ':src/style.scss')
  end

  def test_unstaged_edits_to_the_stylesheet_and_checker_are_preserved
    @source.write('deprecated')
    @repository.join('src/bin/check-staged').write('exit 9')
    install_hook

    assert run_hook.success?
    assert_equal %w[i18n:check styles:check], calls
    assert_equal 'deprecated', @source.read
    assert_equal 'valid', git('show', ':src/style.scss')
  end

  def test_path_limited_commit_uses_the_index_git_prepares_for_that_commit
    git('commit', '--quiet', '-m', 'Base')
    install_hook
    @source.write('deprecated')
    git('add', 'src/style.scss')
    @repository.join('src/Gemfile').write("# Commit only this file\n")

    git('commit', '--quiet', '-m', 'Partial commit', '--', 'src/Gemfile')
    assert_equal %w[i18n:check styles:check], calls
    assert_equal 'valid', git('show', 'HEAD:src/style.scss')
    assert_equal 'deprecated', git('show', ':src/style.scss')
  end

  def test_commit_omits_intent_to_add_files_and_preserves_the_marker
    rails = @repository.join('src/bin/rails')
    rails.write("#!/bin/sh\ntest ! -e proposed.scss\n")
    git('add', 'src/bin/rails')
    proposed = @repository.join('src/proposed.scss')
    proposed.write('work in progress')
    git('add', '--intent-to-add', 'src/proposed.scss')
    install_hook

    git('commit', '--quiet', '-m', 'Tracked files only')
    assert_empty git('ls-tree', 'HEAD', 'src/proposed.scss')
    assert_equal " A src/proposed.scss\n", git('status', '--short', '--', 'src/proposed.scss')
    assert_equal 'work in progress', proposed.read
  end

  def test_staged_bundle_honors_the_checkouts_effective_frozen_setting
    config = @repository.join('src/.bundle/config')
    config.dirname.mkpath
    @repository.join('src/Gemfile.lock').write(<<~LOCKFILE)
      GEM
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES

      BUNDLED WITH
         #{Bundler::VERSION}
    LOCKFILE
    rails = @repository.join('src/bin/rails')
    rails.write(<<~'RUBY')
      #!/usr/bin/env ruby
      require 'bundler'
      abort 'Expected the staged lockfile' unless File.identical?(Bundler.default_lockfile, 'Gemfile.lock')
      File.open(ENV.fetch('CHECK_CALLS'), 'a') { |log| log.puts(!!Bundler.frozen_bundle?) }
    RUBY
    git('add', 'src/bin/rails', 'src/Gemfile.lock')
    install_hook

    ['BUNDLE_FROZEN: "true"', 'BUNDLE_DEPLOYMENT: "true"',
     "BUNDLE_DEPLOYMENT: \"true\"\nBUNDLE_FROZEN: \"false\""].each do |settings|
      config.write("---\n#{settings}\n")
      assert run_hook.success?, @hook_output
    end
    assert_equal %w[true true false], calls
  end

  def test_ci_hook_keeps_deprecations_nonblocking
    install_hook
    assert run_hook(ci: 'true').success?
    assert_equal ['i18n:check'], calls
  end

  def test_a_failed_check_blocks_the_hook
    install_hook
    assert_equal 7, run_hook(failing: 'i18n:check').exitstatus
    assert_equal ['i18n:check'], calls
    @calls.unlink
    assert_equal 7, run_hook(failing: 'styles:check').exitstatus
    assert_equal %w[i18n:check styles:check], calls
  end

  def test_installing_outside_a_git_repository_fails_clearly
    other = @directory.join('not a repository')
    other.mkpath
    error = assert_raises(SystemExit) { install_hook(repository: other) }
    assert_match(/Cannot configure the Git pre-commit hook/, error.message)
  end

  private

  def calls
    @calls.readlines(chomp: true)
  end

  def git(*args, repository: @repository)
    output, status = run_git(*args, repository: repository)
    assert status.success?, output
    output
  end

  def configurable_hooks?
    system('git', '-C', @repository.to_s, '-c', 'hook.probe.command=true',
           '-c', 'hook.probe.event=pre-commit', 'hook', 'list', 'pre-commit', out: File::NULL, err: File::NULL)
  end

  def install_hook(repository: @repository, answer: '')
    previous_stdin = $stdin
    $stdin = StringIO.new(answer)
    Rails.stub(:root, repository.join('src')) do
      task = Rake::Task['i18n:install_hook']
      task.reenable
      capture_io { task.invoke }
    end
  ensure
    $stdin = previous_stdin
  end

  def run_hook(repository: @repository, ci: nil, failing: nil)
    @hook_output, status = run_git('hook', 'run', 'pre-commit', repository: repository, ci: ci, failing: failing)
    status
  end

  def run_git(*args, repository:, ci: nil, failing: nil)
    # Start the fixture's Ruby as Git would from a shell outside the Rails test bundle.
    env = { 'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil, 'BUNDLE_APP_CONFIG' => nil,
            'BUNDLE_LOCKFILE' => repository.join('src/Gemfile.lock').to_s,
            'CHECK_CALLS' => @calls.to_s, 'CI' => ci, 'FAILING_CHECK' => failing }
    Open3.capture2e(env, 'git', '-C', repository.to_s, *args)
  end
end
