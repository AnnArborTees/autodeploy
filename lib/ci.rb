require_relative 'rails_app'
require_relative 'test_app'
require_relative 'shopify_app'

require 'byebug'

non_flag_arguments = ARGV.reject { |a| a.include?('--') }

APP_DIR = non_flag_arguments[0]
APP_TYPE = non_flag_arguments[1]

if APP_DIR.nil? || APP_TYPE.nil?
  STDERR.puts "Usage: ruby ci.rb <app dir> <app type> [--force|--once|--log]"
  exit 1
end

def force?
  ARGV.include?('--force')
end

def run_once?
  ARGV.include?('--once') || force?
end

def log?
  ARGV.include?('--debug')
end

def debug?
  ARGV.include?('--debug')
end

if log?
  $logger = Logger.new(STDOUT)
  $logger.level = Logger::DEBUG
  ActiveRecord::Base.logger = $logger
end

case APP_TYPE
when 'rails' then app = RailsApp.new(APP_DIR)
when 'test' then app = TestApp.new(APP_DIR)
when 'shopify' then app = ShopifyApp.new(APP_DIR)
else raise "Error: unknown app type #{APP_TYPE.inspect}"
end

ENV['RAILS_ENV'] = 'test'
ENV['SSHKIT_COLOR'] = 'true'

loop do
  if force?
    #
    # Don't bother pulling code if --force was specified
    #
    puts "Not going to bother pulling -- running with #{app.commit}"
  else
    #
    # Pull until we have new code
    #
    app.pull_until_new_code!

    puts "New code found! HEAD is now #{app.commit}"

    #
    # See if we already have a run started for this commit
    #
    if !run_once? && Run.exists?(commit: app.commit)
      puts "Run already exists for #{app.commit}"
      next
    end
  end

  puts "Beginning run for #{app.commit}"

  #
  # Set up the 'run' entry in the database, and
  # let the app do the talking from there.
  #
  run = app.create_run
  run.current_output_field = 'spec_output'

  begin
    app.in_app_dir do
      next unless app.run_setup_commands!(run)

      run.specs_started
      unless app.run_tests!(run)
        run.specs_failed
        next
      end

      run.current_output_field = 'deploy_output'

      run.deploy_started
      unless app.deploy!(run)
        run.deploy_failed
        next
      end

      run.deployed
    end

  rescue StandardError => error
    message = "CI ENCOUNTERED ERROR\n#{error.class}: #{error.message}"
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
