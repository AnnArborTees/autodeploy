require_relative 'rails_app'
require_relative 'test_app'
require_relative 'shopify_app'
require_relative 'args'

class CI
  attr_reader :arguments
  attr_reader :app
  attr_reader :thread

  def initialize(argv)
    @arguments = parse_command_line_arguments(argv)

    case @arguments.app_type
    when 'rails' then @app = RailsApp.new(@arguments.app_dir)
    when 'test' then @app = TestApp.new(@arguments.app_dir)
    when 'shopify' then @app = ShopifyApp.new(@arguments.app_dir)
    else raise "Error: unknown app type #{@arguments.app_type.inspect}"
    end

    if @arguments.debug
      $debug_logger ||= Logger.new(STDOUT)
      $debug_logger.level = Logger::DEBUG
      ActiveRecord::Base.logger = $debug_logger
    end
  end

  def status
    if @thread.nil?
      "No thread"
    elsif @thread.status == nil
      "Thread died (exited abnormally)"
    elsif @thread.status == false
      "Thread terminated (reached end of execution)"
    else
      @thread[:ci_status] || "No status"
    end
  end

  def create_thread!(options = {})
    if @thread && @thread.alive? && @thread != Thread.current
      @thread.kill
      sleep 0.1
    end

    # Local variables for the thread
    force = !options.empty? || @arguments.force
    run_once = force || @arguments.run_once
    branches = options[:branches] || @arguments.branches
    deploy_branch = options[:deploy_branch] || @arguments.deploy_branch

    # If options were supplied, we want to start the thread over like normal
    if options.empty?
      callback = -> { }
    else
      callback = -> { create_thread! }
    end

    @thread = Thread.new { LOOP[@app, force, run_once, branches, deploy_branch, callback] }
  end

  LOOP = lambda do |app, force, run_once, branches, deploy_branch, callback|
    begin
      loop do
        if force
          #
          # Don't bother pulling code if --force was specified
          #
          puts "WARNING: only running on first given branch: #{branches.first}" if branches.size > 1
          app.checkout! branches.first
          puts "Not going to bother pulling -- running with #{app.commit} on #{app.branch}"
        else
          #
          # Pull until we have new code
          #
          Thread.current[:ci_status] = "Pulling for #{branches.join(', ')}"
          app.pull_until_new_code!(branches)

          puts "New code found! Branch: #{app.branch}, HEAD is now #{app.commit}"

          #
          # See if we already have a run started for this commit
          #
          if !run_once? && Run.exists?(commit: app.commit)
            puts "Run already exists for #{app.commit}"
            next
          end
        end

        begin_message = "Beginning run for #{app.commit} on #{app.branch}"
        puts begin_message
        Thread.current[:ci_status] = begin_message

        #
        # Set up the 'run' entry in the database, and
        # let the app do the talking from there.
        #
        run = app.create_run
        run.current_output_field = 'spec_output'

        begin
          app.in_app_dir do
            next unless app.run_setup_commands!(run)

            Thread.current[:ci_status] = "Running tests"

            run.specs_started
            unless app.run_tests!(run)
              Thread.current[:ci_status] = "Specs failed"
              run.specs_failed
              next
            end

            if run.branch == deploy_branch
              run.current_output_field = 'deploy_output'

              Thread.current[:ci_status] = "Deploying"

              run.deploy_started
              unless app.deploy!(run)
                run.deploy_failed
                Thread.current[:ci_status] = "Deploy failed"
                next
              end

              Thread.current[:ci_status] = "Deployed"
              run.deployed
            else
              Thread.current[:ci_status] = "Specs passed"
              run.specs_passed
            end
          end

        rescue StandardError => error
          message = "CI ENCOUNTERED ERROR\n#{error.class}: #{error.message}"
          Thread.current[:ci_status] = message
          run.errored(message) rescue nil
          STDERR.puts "#{message}\n\n#{error.backtrace.map { |b| "* #{b}" }.join("\n")}\n"

        rescue Exception => exception
          run.errored("#{exception.class}: #{exception.message}") rescue nil
          raise
        end

        #
        # Exit before looping if this run was forced
        #
        break if run_once?
      end

    rescue Exception => exception
      message = "Exception in CI loop! #{exception.message}"
      Thread.current[:ci_status] = message
      puts message
      callback.call
      exit 1
    end

    callback.call
  end
end
