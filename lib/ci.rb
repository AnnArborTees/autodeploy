require_relative 'rails_app'
require_relative 'test_app'

require 'byebug'

APP_DIR = ARGV[0]
APP_TYPE = ARGV[1]

if APP_DIR.nil? || APP_TYPE.nil?
  STDERR.puts "Usage: ruby ci.rb <app dir> <app type> [--force|--once]"
  exit 1
end

def force?
  ARGV.include?('--force')
end

def run_once?
  ARGV.include?('--once') || force?
end

case APP_TYPE
when 'rails' then app = RailsApp.new(APP_DIR)
when 'test' then app = TestApp.new(APP_DIR)
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
    if Run.exists?(commit: app.commit)
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

    app.deployed
  end

  #
  # Exit before looping if this run was forced
  #
  break if run_once?
end
