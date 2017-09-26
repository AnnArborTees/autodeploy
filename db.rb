#!/bin/ruby

require 'mysql2'
require 'json'

module Util
  def date(time)
    time.strftime("%Y-%m-%d %H:%M:%S")
  end

  def newline
    "\"\\n\""
  end
end

class Command
  include Util

  def initialize
    config = JSON.parse(IO.read("#{ENV['HOME']}/autodeploy.json"))
    db     = config.delete('database')

    @client = Mysql2::Client.new(config)

    if db
      db = @client.escape(db)
      @client.query("CREATE DATABASE #{db}") rescue nil
      @client.query("USE #{db}")
    end
  end

  def init
    table_exists = @client.query("SHOW TABLES").to_a.flat_map(&:values).include?("runs")
    return if table_exists

    @client.query(
      "CREATE TABLE runs ("\
        "id            int          NOT NULL PRIMARY KEY AUTO_INCREMENT, "\
        "app           varchar(255) NOT NULL, "\
        "branch        varchar(255) NOT NULL, "\
        "status        varchar(255) NOT NULL, "\
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

  def new_run(app, branch)
    app    = @client.escape(app)
    branch = @client.escape(branch)

    @client.query(
      "INSERT INTO runs (app, branch, created_at, status) "\
      "VALUES ('#{app}', '#{branch}', NOW(), 'initialized')"
    )
    puts @client.last_id.to_s
  end

  def run_errored(run_id, message)
    message = @client.escape(message)
    run_id = @client.escape(run_id)

    @client.query(
      "UPDATE runs SET status = 'error', spec_output = '#{message}' "\
      "WHERE id = #{run_id}"
    )
  end

  def record_specs(run_id)
    run_id = @client.escape(run_id)

    @client.query("UPDATE runs SET status = 'specs_started', specs_started_at = NOW() WHERE id = #{run_id}")

    begin
      while (input = gets)
        puts input

        @client.query(
          "UPDATE runs SET spec_output = " \
          "CONCAT(spec_output, #{newline}, #{@client.escape(input)}) " \
          "WHERE id = #{run_id}"
        )
      end
    rescue Errno::ENOENT
    end

    @client.query("UPDATE runs SET status = 'specs_ended', specs_ended_at = NOW() WHERE id = #{run_id}")
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
