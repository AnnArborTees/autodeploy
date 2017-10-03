#!/bin/ruby

require 'mysql2'
require 'json'
require 'strscan'
require 'cgi'

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
    # Get rid of bash color codes (adopted from https://stackoverflow.com/a/19890227)
    input = CGI::escapeHTML(input)
    ansi = StringScanner.new(input)
    html = StringIO.new
    until ansi.eos?
      if ansi.scan(/\e\[0?m/)
        html.print(%{</span>})
      elsif ansi.scan(/\e\[0?;?(\d+)m/)
        html.print(%{<span class="#{AnsiColor[ansi[1]]}">})
      else
        html.print(ansi.scan(/./m))
      end
    end

    # Escape for SQL
    @client.escape(html.string)
  end

  def sanitize_commit(commit)
    sanitize(commit.gsub("commit ", ''))
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
    config = JSON.parse(IO.read("#{ENV['HOME']}/autodeploy.json"))
    db     = config.delete('database')

    @client = Mysql2::Client.new(config)

    if db
      db = sanitize(db)
      @client.query("CREATE DATABASE #{db}") rescue nil
      @client.query("USE #{db}")
    end
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
        "created_at        datetime, "\
        "specs_started_at  datetime, "\
        "specs_ended_at    datetime, "\
        "deploy_started_at datetime, "\
        "deploy_ended_at   datetime, "\
        "spec_output       longtext, "\
        "deploy_output     longtext"\
      ")"
    )
  end

  # ================================
  # Creates a new run and outputs its ID for future commands
  # --------------------------------
  def new_run(app, branch, commit)
    app    = sanitize(app)
    branch = sanitize(branch)
    commit = sanitize_commit(commit)

    @client.query(
      "INSERT INTO runs (app, branch, commit, created_at, status) "\
      "VALUES ('#{app}', '#{branch}', '#{commit}', NOW(), 'initialized')"
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

      while (input = STDIN.gets)
        puts input

        @client.query(
          "UPDATE runs SET #{output_field} = " \
          "CONCAT(#{output_field}, '#{sanitize(input)}') " \
          "WHERE id = #{run_id}"
        )
      end

      @client.query("UPDATE runs SET status = '#{operation}_ended', #{operation}_ended_at = NOW() WHERE id = #{run_id}")
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




command = Command.new
action = ARGV[0].gsub('-', '_')

unless command.respond_to?(action)
  STDERR.puts "Bad command #{ARGV[0].inspect}"
  exit(1)
end

begin
  command.send(action, *ARGV[1..-1])
rescue => e
  puts "=== ERROR DURING ACTION: #{ARGV[0]} #{ARGV[1..-1]} ==="
  puts "#{e.class}: #{e.message}"
  e.backtrace.each do |line|
    puts " * #{line}"
  end
end
