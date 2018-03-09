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

    @commit = in_app_dir { Git.commit_hash }
  end

  def create_run
    in_app_dir do
      Run.create!(
        app:       name,
        commit:    commit,
        author:    Git.commit_author,
        message:   Git.commit_message,
        branch:    Git.branch,
        runner_ip: "#{Util.local_username}@#{Util.own_ip_address}"
      )
    end
  end

  def pull_until_new_code!
    in_app_dir do
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

  def run_setup_commands!(run)
    setup_commands.each do |command|
      succeeded = run.record_process(*command)

      unless succeeded
        run.errored("Failed to execute `#{command.join(' ')}`")
        return false
      end
    end

    true
  end

  def run_tests!(_run)
    raise "`run_tests!` unimplemented in #{self.class.name}"
  end

  def deploy!(run)
    run.record(*deploy_command)
  end

  def in_app_dir(&block)
    Dir.chdir(@directory, &block)
  end

  protected

  def setup_commands
    raise "`setup_commands` unimplemented in #{self.class.name}"
  end

  def deploy_command
    raise "`deploy_command` unimplemented in #{self.class.name}"
  end
end
