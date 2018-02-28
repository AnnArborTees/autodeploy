require 'open3'

module Git
  def commit_hash
    # The first line of `git show HEAD` is "commit abc123".
    # So, we split off the "commit" part and return the rest.
    #
    stdin, stdout, _process = Open3.popen2('git', 'show', 'HEAD')
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

  extend self
end
