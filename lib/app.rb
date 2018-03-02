require_relative 'git'
require_relative 'run'
require_relative 'util'

class App
  # We select a random delay time to decrease the chances of
  # both CI machines pulling the same commit.
  DELAY_BETWEEN_PULLS = (5.0...15.0)

  attr_reader :directory
  attr_reader :name
  attr_reader :commit

  def initialize(directory)
    @directory = directory
    @name = File.basename(@directory)

    @commit = chdir { Git.commit_hash }
  end

  def create_run
    chdir do
      Run.create!(
        app:       name,
        commit:    commit,
        author:    Git.commit_author,
        message:   Git.commit_message,
        runner_ip: "#{Util.local_username}@#{Util.own_ip_address}"
      )
    end
  end

  def pull!
    chdir do
      new_commit = Git.commit_hash

      # Keep resetting and pulling until the commit hash changes
      # -- then we know we have new code.
      while new_commit == @commit
        sleep rand(DELAY_BETWEEN_PULLS)
        Git.reset_hard!
        Git.pull!

        new_commit = Git.commit_hash
      end

      @commit = new_commit
    end
  end

  def setup!(_run)
    raise "Implement this in a subclass!"
  end

  def run_tests!(_run)
    raise "Implement this in a subclass!"
  end

  def deploy!(_run)
    raise "Implement this in a subclass!"
  end


  protected

  def chdir(&block)
    Dir.chdir(@directory, &block)
  end
end
