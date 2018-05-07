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

  def try_pulling!(branches, deploy_branch)
    in_app_dir do
      Git.fetch

      # Check out the next branch
      branch_index = ((branches.index(Git.branch) || -1) + 1) % branches.size
      Git.reset_hard!

      if branches[branch_index] == deploy_branch
        # When pulling master, just reset then checkout
        Git.checkout branches[branch_index]

        old_commit = Git.commit_hash
        Git.pull!
        new_commit = Git.commit_hash
      else
        # When pulling non-master, destroy local branch then re-checkout
        old_commit = Git.commit_hash(branches[branch_index])
        Git.delete_branch(branches[branch_index])

        Git.checkout branches[branch_index]
        new_commit = Git.commit_hash
      end

      if new_commit != old_commit
        # FOUND NEW COMMIT!
        @branch = branches[branch_index]
        @commit = new_commit
        true
      else
        false
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

  #
  # This method gets called instead of run_tests_and_deploy! when
  # a request is being processed for this app.
  #
  def handle_request!(request, run, deploy_branch)
    raise "#{self.class.name} can't handle requests!"
  end

  #
  # This method is in charge of calling run_tests!, then deploy!
  # based on test success.
  #
  def run_tests_and_deploy!(run, deploy_branch)
    return unless run_setup_commands!(run)

    Thread.current[:ci_status] = "Running tests"

    run.specs_started
    if run_tests!(run)
      deploy_if_necessary!(run, deploy_branch)
    else
      Thread.current[:ci_status] = "Specs failed"
      run.specs_failed
    end
  end

  def in_app_dir(&block)
    Dir.chdir(@directory, &block)
  end

  protected

  def deploy_if_necessary!(run, deploy_branch)
    Git.fetch
    master_commit = Git.commit_hash("origin/#{deploy_branch}")
    if run.commit == master_commit
      run.current_output_field = 'deploy_output'

      Thread.current[:ci_status] = "Deploying"

      run.deploy_started
      unless deploy!(run)
        run.deploy_failed
        Thread.current[:ci_status] = "Deploy failed"
        return
      end

      Thread.current[:ci_status] = "Deployed"
      run.deployed
    else
      Thread.current[:ci_status] = "Specs passed"
      run.deploy_output ||= ""
      run.deploy_output += "\nDeploy not attempted because specs were run on #{run.commit}, "\
        "but origin/#{deploy_branch} is on #{master_commit}."
      run.specs_passed
    end
  end

  def setup_commands
    raise "`setup_commands` unimplemented in #{self.class.name}"
  end

  def deploy_commands
    raise "`deploy_commands` unimplemented in #{self.class.name}"
  end
end
