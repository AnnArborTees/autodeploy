require_relative 'git'
require_relative 'run'
require_relative 'util'

require 'digest'

class App
  # We select a random delay time to decrease the chances of
  # both CI machines pulling the same commit.
  DELAY_BETWEEN_PULLS = (5.0...15.0)

  attr_reader :directory
  attr_reader :name
  attr_reader :commit
  attr_reader :branch

  def initialize(directory)
    @directory = directory
    @name = File.basename(@directory)
  end

  def checkout!(branch)
    in_app_dir do
      Git.checkout branch
      @branch = Git.branch
      @commit = Git.commit_hash
    end
  end

  def unique_port
    1000 + Digest::MD5.digest(name).bytes.inject { |a,b| (a<<8)+b } % 9000
  end

  def available_branches
    in_app_dir { Git.branches }
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

  def pull_until_new_code!(branches)
    in_app_dir do
      Git.fetch

      branch_index = branches.index(Git.branch) || 0
      Git.checkout branches[branch_index]

      loop do
        # Reset then Pull (the reset is because sometimes files get leftover)
        old_commit = Git.commit_hash
        Git.reset_hard!
        Git.pull!
        new_commit = Git.commit_hash

        if new_commit != old_commit
          # FOUND NEW COMMIT!
          @branch = branches[branch_index]
          @commit = new_commit
          break
        else
          # Delay, then try the next branch
          sleep rand(DELAY_BETWEEN_PULLS) / branches.size.to_f
          branch_index = (branch_index + 1) % branches.size
          Git.checkout branches[branch_index]
        end
      end
    end
  end

  def run_setup_commands!(run)
    setup_commands.each do |command|
      succeeded = run.record_process(*command)

      unless succeeded
        run.errored("Failed to execute `#{command.join(' ')}` for setup")
        return false
      end
    end

    true
  end

  def run_tests!(_run)
    raise "`run_tests!` unimplemented in #{self.class.name}"
  end

  def deploy!(run)
    deploy_commands.each do |command|
      succeeded = run.record_process(*command)

      unless succeeded
        run.errored("Failed to execute `#{command.join(' ')}` for deploy")
        return false
      end
    end

    true
  end

  def in_app_dir(&block)
    Dir.chdir(@directory, &block)
  end

  protected

  def setup_commands
    raise "`setup_commands` unimplemented in #{self.class.name}"
  end

  def deploy_commands
    raise "`deploy_commands` unimplemented in #{self.class.name}"
  end
end
