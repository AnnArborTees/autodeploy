require_relative 'rails_app'

require 'byebug'

# We select a random delay time to decrease the chances of
# both CI machines pulling the same commit.
DELAY_BETWEEN_PULLS = (5.0...15.0)
APP_DIR = ARGV[0]
APP_TYPE = ARGV[1]

if APP_DIR.nil? || APP_TYPE.nil?
  STDERR.puts "Usage: ruby ci.rb <app dir> <app type> [--force]"
  exit 1
end

def force?
  ARGV.include?('--force')
end

case APP_TYPE
when 'rails' then app = RailsApp.new(APP_DIR)
else raise "Error: unknown app type #{APP_TYPE.inspect}"
end

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
    app.pull!

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
  # Create a db entry for this run
  #
  run = app.create_run

  #
  # Perform any setup commands necessary (install dependencies, set up db, etc.)
  #
  next unless app.setup!(run)

  #
  # Run specs
  #
  run.specs_started
  next unless app.run_tests!(run)

  #
  # Deploy
  #
  app.deploy!(run)

  #
  # Exit before looping if this run was forced
  #
  exit 0 if force?
end
