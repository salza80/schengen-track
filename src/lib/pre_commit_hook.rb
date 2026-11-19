# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'pathname'
require 'tempfile'

class PreCommitHook
  # Read the checker itself from the same index Git is committing.
  COMMAND = 'checker=$(git show :src/bin/check-staged) && cd src && exec ruby -C.. -e "$checker"'
  HOOK_SCRIPT = "#!/bin/sh\n#{COMMAND}\n"
  CONFIG_KEY = 'hook.schengen-local-checks'
  # Git invokes the configured command before the hook file. Another worktree
  # may still select our file even after this worktree selects a shared path.
  CONFIGURED_COMMAND = <<~SH.chomp
    hook=$(git rev-parse --git-path hooks/pre-commit) || exit 1
    if [ -f "$hook" ] && [ -x "$hook" ] && cmp -s "$hook" - <<'SCHENGEN_HOOK'
    #{HOOK_SCRIPT.chomp}
    SCHENGEN_HOOK
    then
      exit 0
    fi
    #{COMMAND}
  SH
  PROJECT_COMMANDS = [COMMAND, CONFIGURED_COMMAND].freeze

  def initialize(repository)
    @repository = repository.realpath
  end

  def install
    common = Pathname.new(git('rev-parse', '--path-format=absolute', '--git-common-dir'))
    configured = config_value('core.hooksPath', '--path')
    root = configured ? @repository : common
    directory = Pathname.new(configured || 'hooks')
    hook = root.join(directory, 'pre-commit')

    # Absolute paths, parent traversals and symlinks can lead to hooks used by
    # other projects. Register alongside those hooks in repository config.
    shared = directory.absolute? || directory.each_filename.include?('..') ||
      hook.ascend.take_while { |path| path != root }.any?(&:symlink?)
    if (shared || PROJECT_COMMANDS.include?(config_value("#{CONFIG_KEY}.command", '--local'))) && configurable_hooks?
      register_local_hook
      # Keep using the repository registration after a path change. Retire only
      # our own launcher if it is active again in a repository-owned directory.
      hook.unlink if !shared && hook.file? && hook.binread(HOOK_SCRIPT.bytesize + 1) == HOOK_SCRIPT
      return
    end
    if shared
      abort 'This hooks path is shared. Use Git with configurable hooks (git hook list), or invoke src/bin/check-staged from your hook manager for this repository.'
    end

    if hook.exist?
      puts "Pre-commit hook already exists at #{hook}."
      print 'Overwrite? (y/N): '
      return unless $stdin.gets.to_s.strip.casecmp?('y')
    end

    FileUtils.mkdir_p(hook.dirname)
    # Rename also avoids modifying the target of an existing hard link.
    Tempfile.create('pre-commit', hook.dirname) do |file|
      file.write(HOOK_SCRIPT)
      file.chmod(0o755)
      file.close
      File.rename(file.path, hook)
    end
    puts "Installed pre-commit hook at #{hook}"
  end

  private

  def configurable_hooks?
    # A configured probe makes 'hook list' succeed even in an empty hooks directory.
    _, _, supported = git_result('-c', 'hook.schengen-probe.event=pre-commit',
                                 '-c', 'hook.schengen-probe.command=true', 'hook', 'list', 'pre-commit')
    supported.success?
  end

  def register_local_hook
    command = config_value("#{CONFIG_KEY}.command")
    if command && !PROJECT_COMMANDS.include?(command)
      abort "Git hook name #{CONFIG_KEY} is already used by a different command."
    end
    git('config', '--local', '--replace-all', "#{CONFIG_KEY}.command", CONFIGURED_COMMAND)
    git('config', '--local', '--replace-all', "#{CONFIG_KEY}.event", 'pre-commit', '^pre-commit$')
    puts 'Registered the pre-commit check in repository-local Git configuration.'
  end

  def config_value(key, *options)
    output, error, status = git_result('config', *options, '--get', key)
    return output.chomp if status.success?
    return if status.exitstatus == 1
    abort "Cannot read #{key}: #{error.strip}"
  end

  def git(*args)
    output, error, status = git_result(*args)
    abort "Cannot configure the Git pre-commit hook: #{error.strip}" unless status.success?
    output.chomp
  end

  def git_result(*args)
    Open3.capture3('git', '-C', @repository.to_s, *args)
  end
end
