require_relative 'app'
require 'open3'

class RailsApp < App
  def setup_commands
    [
      %w(bin/rails db:environment:set RAILS_ENV=test),
      %w(bundle install),
      %w(bundle exec rake db:create db:reset)
    ]
  end

  def run_tests!(run)
    at_end = false
    failed_specs = []

    #
    # First, run rspec on everything
    #
    rspec_succeeded = run.record('bundle', 'exec', 'rake', 'spec:all', 'RAILS_ENV=test') do |line|
      if !at_end
        # Once we see "Failed examples:", we can start gathering a list
        # of all failed specs.
        at_end = line.include?("Failed examples:")

      elsif (failed_spec = parse_failed_spec_file(line))
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
      retry_failed_specs!(run, failed_specs)
    end

    #
    # If we reported no failures, we're golden!
    #
    run.failures.empty? && !run.errored?
  end

  def handle_request!(request, run, deploy_branch)
    case request.action
    when 'retry'
      if request.failure
        retry_failure!(request, run, deploy_branch)
      elsif request.run
        retry_run!(request, run, deploy_branch)
      else
        raise "Got retry request with no target!"
      end

    else
      raise "Rails app can't handle #{request.action} requests"
    end
  end

  def deploy_commands
    [
      %w(bundle exec cap production deploy)
    ]
  end

  protected

  def retry_failed_specs!(run, failed_specs)
    failed_spec_info = []
    spec_output = []

    run.failures.destroy_all

    failed_specs.shuffle.each do |file|
      spec_output.clear

      run.send_to_output "===== Retrying failed spec: #{file} =====\n\n"
      passed = run.record('bundle', 'exec', 'rspec', file, '--format=documentation') do |line, is_stderr|
        spec_output << line unless is_stderr
      end

      unless passed
        html_output = Util.color2html(spec_output.join)
        raw_output = Util.uncolor(spec_output.join)

        run.failures.create!(output: html_output)

        # NOTE failed_spec_info is for the failure email
        failed_spec_info << {
          file: file,
          raw_output: raw_output,
          output: html_output
                    .gsub("\n", "<br />")
                    .gsub('   ', ' &nbsp;&nbsp;')
                    .gsub('  ', ' &nbsp;')
        }
      end
    end

    # Send results email
    if failed_spec_info.empty?
      send_success_email(run)
    else
      send_failures_email(failed_spec_info, run)
    end
  end


  def retry_failure!(request, run, deploy_branch)
    failure = request.failure

    Git.checkout(failure.run.commit)

    #
    # Find the spec to run in the output
    #
    file = nil
    puts "LOOKING FOR 'RSPEC:'"
    failure.output.each_line do |line|
      if (failed_spec = parse_failed_spec_file(line))
        file = failed_spec
      end
    end
    raise "Couldn't find spec file in failure output\n#{Util.uncolor(failure.output)}" if file.nil?

    #
    # Run the spec
    #
    run.retrying_specs
    spec_output = []
    error_output = []
    run.send_to_output "===== Retrying failed spec: #{file} =====\n\n"
    passed = run.record('bundle', 'exec', 'rspec', file, '--format=documentation') do |line, is_stderr|
      if is_stderr
        error_output << line
      else
        spec_output << line
      end
    end

    #
    # Update the failure's output, or destroy it
    #
    if passed
      failure.destroy!
      run.specs_passed
      deploy_if_necessary!(run, deploy_branch) if run.reload.failures.empty?
    else
      run.specs_failed

      if spec_output.empty?
        joined_output = Util.color2html(error_output.join)
      else
        joined_output = Util.color2html(spec_output.join)
      end
      failure.update_column :output, "== RETRIED ==\n#{joined_output}\n"\
                                     "--------------------------\n#{failure.output}"
    end
  end

  def retry_run!(request, run, deploy_branch)
    run.update_column :spec_output, "=== RETRY ===\n"
    run.update_column :deploy_output, ''
    run_tests_and_deploy!(run, deploy_branch)
  end


  def parse_failed_spec_file(line)
    if /rspec\s+(?<failed_spec>[\w\.\/:\[\]]+)/ =~ Util.uncolor(line.strip)
      failed_spec
    end
  end


  def send_failures_email(failed_spec_info, run)
    send_email(
      failed_spec_info,
      run,
      "failed_specs_email",
      "❌ Specs Failed: #{run.app} #{run.branch} #{datestamp}"
    )
  end

  def send_success_email(run)
    send_email(
      {},
      run,
      "passed_specs_email",
      "✔ Specs Passed: #{run.app} #{run.branch} #{datestamp}"
    )
  end

  def send_email(failed_spec_info, run, template_name, subject)
    raise "No aws-sdk-ses gem found" unless defined?(Aws::SES)
    raise "No ERB gem found" unless defined?(ERB)
    ses = Aws::SES::Client.new

    html_template_path = File.dirname(__FILE__) + "/templates/#{template_name}.html.erb"
    text_template_path = File.dirname(__FILE__) + "/templates/#{template_name}.txt.erb"
    html_renderer = ERB.new(IO.read(html_template_path))
    text_renderer = ERB.new(IO.read(text_template_path))

    timestamp = Time.now.strftime("%A, %d %b %Y %l:%M %p")

    erb_context = Struct.new(:failed_spec_info, :run, :app_name, :timestamp) do
      def get_binding
        binding
      end
    end.new(failed_spec_info, run, run.app, timestamp)

    response = ses.send_email(
      destination: {
        to_addresses: [
          run.author_email
        ]
      },
      message: {
        subject: {
          charset: "UTF-8",
          data: subject
        },
        body: {
          html: {
            charset: "UTF-8",
            data: html_renderer.result(erb_context.get_binding)
          },
          text: {
            charset: "UTF-8",
            data: text_renderer.result(erb_context.get_binding)
          }
        }
      },
      source: "aatci@annarbortees.com"
    )

    puts "Result of sending #{template_name}:"
    puts JSON.pretty_generate response.to_h
  end

  def datestamp
    Time.now.strftime("%m/%d/%Y")
  end
end
