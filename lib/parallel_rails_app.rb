require_relative 'rails_app'

class ParallelRailsApp < RailsApp
  def setup_commands
    [
      %w(bin/rails db:environment:set RAILS_ENV=test),
      %w(bundle install),
      %w(bundle exec rake parallel:create[8]),
      %w(bundle exec rake db:reset),
      %w(bundle exec rake parallel:prepare[8])
    ]
  end

  def run_tests!(run)
    #
    # First, run rspec on everything
    #
    rspec_succeeded = run.record('bundle', 'exec', 'rake', 'spec:parallel_all', 'RAILS_ENV=test')
    return true if rspec_succeeded

    #
    # Gather failed specs
    #
    failed_specs = []
    File.open("tmp/failing_specs.log") do |f|
      while (line = f.gets)
        if (failed_spec = parse_failed_spec_file(line))
          failed_specs << failed_spec
        end
      end
    end

    #
    # Retry failed specs individually
    #
    if !rspec_succeeded && failed_specs.empty?
      run.errored("RSpec failed, but couldn't parse out which ones!")
    elsif !rspec_succeeded
      retry_failed_specs!(run, failed_specs)
    end

    #
    # If we reported no failures, we're golden!
    #
    run.failures.empty? && !run.errored?
  end
end
