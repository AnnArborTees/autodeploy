require 'socket'
require 'mysql2'
require 'strscan'
require 'stringio'
require 'cgi'

require 'aws-sdk-ses'
require 'erb'

class Db
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

  def initialize
    reconnect_client!
  end


  def commit_has_run?(commit)
    app    = sanitize(app)
    commit = sanitize_commit(commit)

    result = @client.query("SELECT COUNT(*) FROM runs WHERE app = '#{app}' AND commit = '#{commit}'")
    # TODO let's try activerecord
  end


  protected

  def date(time)
    time.strftime("%Y-%m-%d %H:%M:%S")
  end

  def newline
    "\"\\n\""
  end

  def sanitize(input, client = nil)
    return '' if input.nil?
    client ||= @client

    # Escape for SQL
    client.escape(color2html(input))
  end

  def color2html(input, client = nil)
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

    html.string
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

  def own_ip_address
    config = read_config
    Socket
      .ip_address_list
      .select { |ip| ip.ipv4_private? }
      .map { |ip| ip.getnameinfo.first }
      .select { |ip| config['subnets'].any? { |sn| ip.start_with?(sn) } }
      .first
  end

  def local_username
    ENV['USER'] || ENV['USERNAME']
  end

  def read_config
    JSON.parse(IO.read("#{ENV['HOME']}/autodeploy.json"))
  end

  def new_client
    config = read_config['mysql2']
    db     = config.delete('database')

    client = Mysql2::Client.new(config)

    if db
      db = sanitize(db, client)
      client.query("CREATE DATABASE #{db}") rescue nil
      client.query("USE #{db}")
    end

    client
  end

  def reconnect_client!
    @client = new_client
  end

  def initialize_tables!
    reconnect_client! if @client.nil?

    runs_table_exists = @client.query("SHOW TABLES").to_a.flat_map(&:values).include?("runs")
    unless runs_table_exists
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

    failures_table_exists = @client.query("SHOW TABLES").to_a.flat_map(&:values).include?("failures")
    unless failures_table_exists
      @client.query(
        "CREATE TABLE failures ("\
          "id            int      NOT NULL PRIMARY KEY AUTO_INCREMENT, "\
          "run_id        int      NOT NULL"\
          "output        longtext NOT NULL"\
        ")"
      )
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
end
