require_relative 'app'
require 'open3'

class RailsApp < App
  def setup!(run)
    unless bundle_install(run)
      run.errored("Failed to bundle install!")
      return false
    end

    unless db_migrate(run)
      run.errored("Failed to set up database!")
      return false
    end

    true
  end

  def run_tests!(run)
    at_end = false
    failed_specs = []

    rspec_succeeded = rspec(run, 'spec') do |line|
      if !at_end
        # Once we see "Failed examples:", we can start gathering a list
        # of all failed specs.
        at_end = input.include?("Failed examples:")

      elsif /^rspec\s+(?<failed_spec>[\w\.\/:]+)/ =~ Util.uncolor(input.strip)
        failed_specs << failed_spec
      end
    end

    if !rspec_succeeded && failed_specs.empty?
      run.errored("RSpec failed, but couldn't parse out which ones!")

      # TODO else, run all failed specs individually.
      # if we want to utilize the "failures" table, then now is a good
      # time.
    end
  end

  private

  def rspec(run, file, &block)
    run.record_process(
      output_to: 'spec_output',
      command: ['bundle', 'exec', 'rspec', file],
      &block
    )
  end

  def bundle_install(run)
    run.record_process(
      output_to: 'spec_output',
      command: %w(bundle install)
    )
  end

  def db_migrate(run)
    run.record_process(
      output_to: 'spec_output',
      command: %w(bundle exec rake db:create db:migrate)
    )
  end
end
