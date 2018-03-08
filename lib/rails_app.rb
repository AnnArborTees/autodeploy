require_relative 'app'
require 'open3'

class RailsApp < App
  def setup_commands
    [
      %w(bundle install),
      %w(bundle exec rake db:create db:migrate)
    ]
  end

  def run_tests!(run)
    at_end = false
    failed_specs = []

    #
    # First, run rspec on everything
    #
    rspec_succeeded = run.record('bundle', 'exec', 'rspec') do |line|
      if !at_end
        # Once we see "Failed examples:", we can start gathering a list
        # of all failed specs.
        at_end = input.include?("Failed examples:")

      elsif /^rspec\s+(?<failed_spec>[\w\.\/:]+)/ =~ Util.uncolor(input.strip)
        # The regex parsed the file name out of the "rspec <filename>" string
        failed_specs << failed_spec
      end
    end

    #
    # If any specs failed, retry all failed specs individually
    # and report the ones that still fail.
    #
    if !rspec_succeeded && failed_specs.empty?
      run.errored("RSpec failed, but couldn't parse out which ones!")
    elsif !rspec_succeeded

      failed_spec_info = []
      spec_output = []

      failed_specs.each do |file|
        spec_output.clear

        run.send_to_output "===== Retrying failed spec: #{file} ====="
        passed = run.record('bundle', 'exec', 'rspec', file) do |line|
          spec_output << line
        end

        unless passed
          joined_output = spec_output.join

          run.failures.create!(output: joined_output)

          # NOTE failed_spec_info is for the failure email
          failed_spec_info << {
            file: file,
            output: color2html(joined_output)
              .gsub("\n", "<br />")
              .gsub('   ', ' &nbsp;&nbsp;')
              .gsub('  ', ' &nbsp;')
          }
        end
      end

      # Send failures email
      send_failures_email(failed_spec_info, run.id, run.app)
    end

    #
    # If we reported no failures, we're golden!
    #
    run.failures.empty?
  end

  def deploy_command
    %w(bundle exec cap production deploy)
  end

  private

  def send_failures_email(failed_spec_info, run_id, app_name)
    return if failed_spec_info.empty?
    raise "No aws-sdk-ses gem found" unless defined?(Aws::SES)
    raise "No ERB gem found" unless defined?(ERB)
    ses = Aws::SES::Client.new

    template_path = File.dirname(__FILE__) + "/failed_specs_email.html.erb"
    html_renderer = ERB.new(IO.read(template_path))

    erb_context = Struct.new(:failed_spec_info, :run_id, :app_name) do
      def get_binding
        binding
      end
    end.new(failed_spec_info, run_id, app_name)

    datestamp = Time.now.strftime("%m/%d/%Y")

    response = ses.send_email(
      destination: {
        to_addresses: [
          # TODO hardcoded email address
          'devteam@annarbortees.com'
        ]
      },
      message: {
        subject: {
          charset: "UTF-8",
          data: "Spec Failures: #{app_name} #{datestamp}"
        },
        body: {
          html: {
            charset: "UTF-8",
            data: html_renderer.result(erb_context.get_binding)
          },
          text: {
            charset: "UTF-8",
            data: "Failed specs:\n#{failed_spec_info.map { |f| f[:file] }.join("\n")}"
          }
        }
      },
      source: "aatci@annarbortees.com"
    )

    puts JSON.pretty_generate response.to_h
  end
end
