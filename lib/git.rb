# frozen_string_literal: true
#
require 'open3'

module Git
  def fetch
    system "git fetch"
  end

  def branch
    # The first line of git status is:
    # "On branch <branch name>"
    #
    stdin, stdout, _process = Open3.popen2('git', 'status')

    while line = stdout.gets
      if /On branch (?<branch_name>[\w\-]+)/ =~ line
        return branch_name

      elsif /HEAD detached at/ =~ line
        return commit_hash
      end
    end
    raise "Failed to find current branch"

  ensure
    stdin.close if stdin
    stdout.close if stdin
  end

  def branches
    # Parse out all the available remote branches.
    #
    stdin, stdout, _process = Open3.popen2('git', 'branch', '-a')

    results = []

    while line = stdout.gets
      line = line.chomp.strip
      prefix = 'remotes/origin/'
      results << line.gsub(prefix, '') if line.start_with?(prefix)
    end

    results

  ensure
    stdin.close
    stdout.close
  end

  def checkout(branch)
    # Switch to given branch.
    #
    stdin, stdout, _process = Open3.popen2e('git', 'checkout', branch)

    lines = []
    while line = stdout.gets
      lines << line.chomp.strip
    end

    expected_lines = [
      "Switched to branch '#{branch}'",       # Checked out local branch
      "Switched to a new branch '#{branch}'", # Checked out new remote branch
      "Already on '#{branch}'",               # Checked out current branch
      "Note: checking out '#{branch}'.",      # Checked out commit (detached HEAD)
      "HEAD is now at #{branch.first(7)}..."  # Checked out current commit (detached HEAD)
    ]

    unless expected_lines.any? { |e| lines.any? { |l| l.include?(e) } }
      raise "Failed to checkout #{branch.inspect}\nExpected one of #{expected_lines}\n\n#{lines.join("\n")}"
    end

    branch

  ensure
    stdin.close
    stdout.close
  end

  def commit_hash(branch = 'HEAD')
    # The first line of `git show HEAD` is "commit abc123".
    # So, we split off the "commit" part and return the rest.
    #
    stdin, stdout, _process = Open3.popen2('git', 'show', branch)
    stdout.gets.split(/\s+/, 2).last.strip

  ensure
    stdin.close
    stdout.close
  end

  def commit_author
    # Grab the first commit log entry and parse out the "Author:"
    # part.
    #
    stdin, stdout, _process = Open3.popen2('git', 'log', '-n', '1')

    while line = stdout.gets
      if line.include?("Author:")
        return line.split(/\s+/, 2).last.strip
      end
    end

  ensure
    stdin.close
    stdout.close
  end

  def commit_message
    # The commit message begins after the first blank line in the
    # log entry.
    #
    stdin, stdout, _process = Open3.popen2('git', 'log', '-n', '1')

    while line = stdout.gets
      break if line.strip.empty?
    end

    stdout.read.strip

  ensure
    stdin.close
    stdout.close
  end

  def pull!
    pid = Process.spawn("git", "pull")
    Process.wait pid
  end

  def reset_hard!
    pid = Process.spawn("git", "reset", "--hard")
    Process.wait pid
  end

  extend self
end
