#!/bin/ruby

require 'mysql2'
require 'json'
require 'strscan'
require 'stringio'
require 'cgi'
require 'socket'
require 'open3'
begin
  require 'aws-sdk-ses'
  require 'erb'
rescue Exception
end

# ================================
# Contains helper methods that are not commands
# --------------------------------
module Util
  AnsiColor = {
    "1" => "bold",
    "4" => "underline",
    "30" => "black",
    "31" => "red",
    "32" => "green",
    "33" => "yellow",
    "34" => "blue",
    "35" => "magenta",
    "36" => "cyan",
    "37" => "white",
    "40" => "bg-black",
    "41" => "bg-red",
    "42" => "bg-green",
    "43" => "bg-yellow",
    "44" => "bg-blue",
    "45" => "bg-magenta",
    "46" => "bg-cyan",
    "47" => "bg-white",
  }

  def date(time)
    time.strftime("%Y-%m-%d %H:%M:%S")
  end

  def newline
    "\"\\n\""
  end

  def sanitize(input)
    return '' if input.nil?

    # Replace bash color codes with html (adopted from https://stackoverflow.com/a/19890227)
    input = CGI::escapeHTML(input)
    ansi = StringScanner.new(input)
    html = StringIO.new
    until ansi.eos?
      if ansi.scan(/\e\[0?m/)
        html.print(%{</span>})
      elsif ansi.scan(/\e\[0?1?;?(\d+)(;49)?m/)
        html.print(%{<span class="#{AnsiColor[ansi[1]]}">})
      else
        html.print(ansi.scan(/./m))
      end
    end

    # Escape for SQL
    @client.escape(html.string)
  end

  def uncolor(input)
    # Get rid of bash color codes (adopted from https://stackoverflow.com/a/19890227)
    ansi = StringScanner.new(input)
    html = StringIO.new
    until ansi.eos?
      if ansi.scan(/\e\[0?m/)
        # Nothing
      elsif ansi.scan(/\e\[0?1?;?(\d+)(;49)?m/)
        # Nothing
      else
        html.print(ansi.scan(/./m))
      end
    end

    html.string
  end

  def sanitize_commit(commit)
    sanitize(commit.gsub("commit ", ''))
  end

  # TODO this is sorta hardcoded to match our AWS VPC settings.
  def own_ip_address
    Socket
      .ip_address_list
      .select { |ip| ip.ipv4_private? }
      .map { |ip| ip.getnameinfo.first }
      .select { |ip| ip =~ /^10\.85/ || ip =~ /^10\.0/ }
      .first
  end

  def local_username
    ENV['USER'] || ENV['USERNAME']
  end

  def read_config
    JSON.parse(IO.read("#{ENV['HOME']}/autodeploy.json"))
  end

  def reconnect_client!
    config = read_config
    db     = config.delete('database')

    @client = Mysql2::Client.new(config)

    if db
      db = sanitize(db)
      @client.query("CREATE DATABASE #{db}") rescue nil
      @client.query("USE #{db}")
    end
  end

  def input_sender_thread(run_id, output_field, &is_done)
    input_queue = Queue.new

    thread = Thread.new do
      loop do
        total_input = ""
        total_input += input_queue.pop until input_queue.empty?

        if total_input.empty?
          break if is_done.call
          next sleep 0.1
        end

        retries = 10
        begin
          @client.query(
            "UPDATE runs SET #{output_field} = " \
            "CONCAT(#{output_field}, '#{sanitize(total_input)}') " \
            "WHERE id = #{run_id}"
          )

        rescue Mysql2::Error => e
          if retries > 0 && e.message.include?("Lost connection") || e.message.include?("server has gone away")
            retries -= 1
            reconnect_client!
            retry
          else
            raise
          end
        end
      end
    end

    [thread, input_queue.method(:<<)]
  end

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
            data: html_renderer.result(erb_context.binding)
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

# ================================
# All methods defined here are commands that can be
# passed via command line (see bottom of file)
# --------------------------------
class Command
  include Util

  # ================================
  # Constructor
  # --------------------------------
  def initialize
    reconnect_client!
  end

  # ================================
  # Called to initialize the database if necessary (on first run)
  # --------------------------------
  def init
    table_exists = @client.query("SHOW TABLES").to_a.flat_map(&:values).include?("runs")
    return if table_exists

    @client.query(
      "CREATE TABLE runs ("\
        "id            int          NOT NULL PRIMARY KEY AUTO_INCREMENT, "\
        "app           varchar(255) NOT NULL, "\
        "branch        varchar(255) NOT NULL, "\
        "status        varchar(255) NOT NULL, "\
        "commit        varchar(255) NOT NULL, "\
        "runner_ip     varchar(255), "\
        "author        varchar(255), "\
        "created_at        datetime, "\
        "specs_started_at  datetime, "\
        "specs_ended_at    datetime, "\
        "deploy_started_at datetime, "\
        "deploy_ended_at   datetime, "\
        "spec_output       longtext, "\
        "message           longtext, "\
        "deploy_output     longtext"\
      ")"
    )
  end

  # ================================
  # Creates a new run and outputs its ID for future commands
  # --------------------------------
  def new_run(app, branch, commit, author, message)
    app     = sanitize(app)
    branch  = sanitize(branch)
    commit  = sanitize_commit(commit)
    ip      = sanitize("#{local_username}@#{own_ip_address}")
    author  = sanitize(author)
    message = sanitize(message)

    @client.query(
      "INSERT INTO runs (app, branch, commit, author, message, created_at, status, runner_ip) "\
      "VALUES ('#{app}', '#{branch}', '#{commit}', '#{author}', '#{message}', NOW(), 'initialized', '#{ip}')"
    )
    puts @client.last_id.to_s
  end

  # ================================
  # Exits with nonzero return code if there already exists
  # a build with the given app and commit.
  # --------------------------------
  def check_commit(app, commit)
    app    = sanitize(app)
    commit = sanitize_commit(commit)

    result = @client.query("SELECT COUNT(*) FROM runs WHERE app = '#{app}' AND commit = '#{commit}'")
    exit result.to_a.first.values.first
  end

  # ================================
  # Sets the run status to 'errored', with a message in spec_output
  # --------------------------------
  def run_errored(run_id, message)
    message = sanitize(message)
    run_id = sanitize(run_id)

    @client.query(
      "UPDATE runs SET status = 'error', spec_output = '#{message}' "\
      "WHERE id = #{run_id}"
    )
  end

  # ================================
  # (Defines record_specs and record_deploy)
  #
  # Pushes all input into spec/deploy_output (`rspec` or `cap` are piped into these commands)
  # --------------------------------
  ['specs', 'deploy'].each do |operation|
    output_field = "#{operation.gsub(/s$/, '')}_output"

    define_method "record_#{operation}" do |run_id|
      run_id = sanitize(run_id)

      @client.query(
        "UPDATE runs SET status = '#{operation}_started', #{operation}_started_at = NOW(), #{output_field} = '' " \
        "WHERE id = #{run_id}"
      )

      done = false
      input_sender, send_input = input_sender_thread(run_id, output_field) { done }

      while (input = STDIN.gets)
        puts input
        send_input.(input)
      end

      done = true
      input_sender.join
      @client.query("UPDATE runs SET status = '#{operation}_ended', #{operation}_ended_at = NOW() WHERE id = #{run_id}")
    end
  end

  # ================================
  # Hacky workaround for randomly failing specs:
  # run rspec normally then run all failures individually.
  # --------------------------------
  def rspec_workaround(run_id, *args)
    run_id = sanitize(run_id)

    @client.query(
      "UPDATE runs SET status = 'specs_started', specs_started_at = NOW(), spec_output = '' " \
      "WHERE id = #{run_id}"
    )

    done = false
    input_sender, send_input = input_sender_thread(run_id, 'spec_output') { done }

    failed_specs = []
    run_rspec = lambda do |file, failed_specs_list, &block|
      _stdin, output, process = Open3.popen2e('bundle', 'exec', 'rspec', file, *args)

      at_end = false

      while (input = output.gets)
        puts input
        block.(input) if block
        send_input.(input)

        # If second arg is an array, fill it with the file paths of failed specs
        if failed_specs_list
          if !at_end
            at_end = input.include?("Failed examples:")

          elsif /^rspec\s+(?<failed_spec>[\w\.\/:]+)/ =~ uncolor(input.strip)
            failed_specs_list << failed_spec
          end
        end
      end

      process.value.success?
    end

    # First run all specs, then run failed specs individually
    everything_passed = run_rspec.('spec', failed_specs)
    failure_count = failed_specs.size
    failed_spec_info = [] # Array of hashes of keys: file, output

    if !everything_passed && failed_specs.empty?
      puts "ERROR: RSpecs failed, but no failed specs were detected!"
      failure_count = 9999999

    elsif !everything_passed
      # Run all failed specs individually
      everything_passed = true

      failed_specs.each do |failed_spec|
        send_input.("\033[1m\033[33m==== RETRYING FAILED SPEC #{failed_spec} ====\033[0m\033[0m\n")

        failed_spec_output = []

        if run_rspec.(failed_spec, nil) { |o| failed_spec_output << o }
          failure_count -= 1
        else
          everything_passed = false
          failed_spec_info << {
            file: failed_spec,
            output: failed_spec_output.join("<br />")
          }
        end
      end
    end

    # Report end result
    if failure_count > 0
      send_input.("\033[1m\033[31m\n==== #{failure_count} Failed specs ====\033[0m\033[0m\n")
    elsif everything_passed
      send_input.("\033[1m\033[32m\n==== SPECS PASSED! Onto deployment ====\033[0m\033[0m\n")
    else
      send_input.("\033[1m\033[31m\n==== Something went awry ====\033[0m\033[0m\n")
    end

    done = true
    input_sender.join
    @client.query("UPDATE runs SET status = 'specs_ended', specs_ended_at = NOW() WHERE id = #{run_id}")

    if everything_passed
      exit 0
    else
      begin
        # Grab app name
        result = @client.query("SELECT app FROM runs WHERE id = '#{run_id}'")
        app = result.to_a.first.values.first

        send_failures_email(failed_spec_info, run_id, app)
      rescue => e
        send_input.("\033[31m\nError sending email:\n#{e.class} #{e.message}\033[0m\n")
      end

      exit 1
    end
  end

  # ================================
  # Updates spec status -- typically to 'specs_passed', 'specs_failed', etc.
  # --------------------------------
  def spec_status(run_id, status)
    run_id = sanitize(run_id)

    @client.query(
      "UPDATE runs SET status = '#{sanitize(status)}' " \
      "WHERE id = #{run_id}"
    )
  end
end




if $0 != 'irb'
  command = Command.new
  action = ARGV[0].gsub('-', '_')

  unless command.respond_to?(action)
    STDERR.puts "Bad command #{ARGV[0].inspect}"
    exit(1)
  end

  begin
    command.send(action, *ARGV[1..-1])
  rescue => e
    STDERR.puts "=== ERROR DURING ACTION: #{ARGV[0]} #{ARGV[1..-1]} ==="
    STDERR.puts "#{e.class}: #{e.message}"
    e.backtrace.each do |line|
      STDERR.puts " * #{line}"
    end
    exit(111)
  end
end
