require_relative 'rails_app'
require_relative 'parallel_rails_app'
require_relative 'test_app'
require_relative 'shopify_app'
require_relative 'args'
require_relative 'request'

class CI
  # We select a random delay time to decrease the chances of
  # both CI machines pulling the same commit.
  DELAY_BETWEEN_PULLS = (1.0...10.0)

  attr_reader :arguments
  attr_reader :app
  attr_reader :thread

  class Error < StandardError
  end

  def initialize(argv)
    @arguments = parse_command_line_arguments(argv)

    case @arguments.app_type
    when 'rails'          then @app = RailsApp.new(@arguments)
    when 'rails_parallel' then @app = ParallelRailsApp.new(@arguments)
    when 'test'           then @app = TestApp.new(@arguments)
    when 'shopify'        then @app = ShopifyApp.new(@arguments)
    else raise Error, "unknown app type #{@arguments.app_type.inspect}"
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

  def start_thread!(options = {})
    if @thread && @thread.alive? && @thread != Thread.current
      @thread.kill
      sleep 0.1
    end

    @thread = Thread.new { start!(options) }
  end

  def start!(options = {})
    force = !options.empty? || @arguments.force
    run_once = force || @arguments.run_once
    branches = options[:branches] || @arguments.branches
    deploy_branch = options[:deploy_branch] || @arguments.deploy_branch

    ci_loop(@app, force, run_once, branches, deploy_branch)
  end

  private

  def ci_loop(app, force, run_once, branches, deploy_branch)
    begin
      loop do
        request = nil

        if force
          #
          # Don't bother pulling code if --force was specified
          #
          puts "WARNING: only running on first given branch: #{branches.first}" if branches.size > 1
          app.checkout! branches.first
          puts "Not going to bother pulling -- running with #{app.commit} on #{app.branch}"
        else
          #
          # Pull until either we have new code, or a request comes in
          #
          Thread.current[:ci_status] = "Pulling for #{branches.join(', ')}"

          loop do
            break if app.try_pulling!(branches, deploy_branch)

            if (pending_request = Request.pending.where(app: app.name).first)
              request = pending_request

              begin
                request.prepare_app!(app, branches)
              rescue => error
                request.update_column :state, 'errored'
                puts "Request errored. #{error.class} #{error.message}"
                next
              end

              break
            end

            sleep rand DELAY_BETWEEN_PULLS
          end

          if request
            puts "Got a request! Branch: #{app.branch}, HEAD is now #{app.commit}"
          else
            puts "New code found! Branch: #{app.branch}, HEAD is now #{app.commit}"
          end
        end

        begin_message = "Beginning #{request ? 'request' : 'run'} for #{app.commit} on #{app.branch}"
        puts begin_message
        Thread.current[:ci_status] = begin_message

        #
        # See if we already have a run started for this commit
        # (unless we're processing a request)
        #
        if !force && !request && !run_once && Run.exists?(commit: app.commit)
          # On master, we might want to just deploy upon receiving an already-run commit
          if app.branch == deploy_branch
            just_deploy = Run.exists?(commit: app.commit, status: 'specs_passed') &&
                          !Run.exists?(commit: app.commit, branch: deploy_branch)
          else
            puts "Run already exists for #{app.commit}"
            next
          end
        end

        #
        # Set up the 'run' entry in the database, and
        # let the app do the talking from there.
        #
        if request && request.run
          run = request.run
        else
          run = app.create_run
        end
        run.current_output_field = 'spec_output'

        begin
          app.in_app_dir do
            if request
              app.handle_request!(request, run, deploy_branch)
              request.update_column :state, 'fulfilled' if request.state == 'in_progress'
            elsif just_deploy
              app.deploy_if_necessary!(run, deploy_branch)
            else
              app.run_tests_and_deploy!(run, deploy_branch)
            end
          end

        rescue StandardError => error
          message = "CI ENCOUNTERED ERROR\n#{error.class}: #{error.message}"
          Thread.current[:ci_status] = message
          run.errored(message) rescue nil
          STDERR.puts "#{message}\n\n#{error.backtrace.map { |b| "* #{b}" }.join("\n")}\n"
          request.update_column :state, 'errored' if request

        rescue Exception => exception
          run.errored("#{exception.class}: #{exception.message}") rescue nil
          request.update_column :state, 'errored' rescue nil
          raise
        end

        #
        # Exit before looping if this run was forced
        #
        break if run_once
      end

    rescue Exception => exception
      message = "Exception in CI loop! #{exception.message}"
      Thread.current[:ci_status] = message
      puts message
      puts exception.backtrace
      exit 1
    end
  end
end
