# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'pathname'
require 'tempfile'

class PreCommitHook
  # Read the checker itself from the same index Git is committing.
  COMMAND = 'checker=$(git show :src/bin/check-staged) && cd src && exec ruby -C.. -e "$checker"'
  CONFIG_KEY = 'hook.schengen-local-checks'

  def initialize(repository)
    @repository = repository.realpath
  end

  def install
    common = Pathname.new(git('rev-parse', '--path-format=absolute', '--git-common-dir'))
    configured, _, status = git_result('config', '--path', '--get', 'core.hooksPath')
    abort 'Cannot read core.hooksPath' unless [0, 1].include?(status.exitstatus)
    root = status.success? ? @repository : common
    directory = status.success? ? Pathname.new(configured.chomp) : Pathname.new('hooks')
    hook = root.join(directory, 'pre-commit')

    # Absolute paths, parent traversals and symlinks can lead to hooks used by
    # other projects. Register alongside those hooks in repository config.
    if directory.absolute? || directory.each_filename.include?('..') ||
        hook.ascend.take_while { |path| path != root }.any?(&:symlink?)
      register_local_hook
      return
    end

    if hook.exist?
      puts "Pre-commit hook already exists at #{hook}."
      print 'Overwrite? (y/N): '
      return unless $stdin.gets.to_s.strip.casecmp?('y')
    end

    FileUtils.mkdir_p(hook.dirname)
    # Rename also avoids modifying the target of an existing hard link.
    Tempfile.create('pre-commit', hook.dirname) do |file|
      file.write("#!/bin/sh\n#{COMMAND}\n")
      file.chmod(0o755)
      file.close
      File.rename(file.path, hook)
    end
    puts "Installed pre-commit hook at #{hook}"
  end

  private

  def register_local_hook
    # A configured probe makes 'hook list' succeed even in an empty hooks directory.
    _, _, supported = git_result('-c', 'hook.schengen-probe.event=pre-commit',
                                 '-c', 'hook.schengen-probe.command=true', 'hook', 'list', 'pre-commit')
    unless supported.success?
      abort 'This hooks path is shared. Use Git with configurable hooks (git hook list), or invoke src/bin/check-staged from your hook manager for this repository.'
    end

    git('config', '--local', '--replace-all', "#{CONFIG_KEY}.command", COMMAND)
    git('config', '--local', '--replace-all', "#{CONFIG_KEY}.event", 'pre-commit')
    puts 'Registered the pre-commit check in repository-local Git configuration.'
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
