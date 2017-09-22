require 'mysql2'
require 'json'

@client = Mysql2::Client.new(JSON.parse("~/autodeploy.json"))

def init
  table_exists = @client.query("SHOW TABLES").to_a.flat_map(&:values).include?("runs")
  return if table_exists

  @client.query(
    "CREATE TABLE runs ("\
      "id      int          NOT NULL AUTO_INCREMENT, "\
      "app     varchar(255) NOT NULL, "\
      "branch  varchar(255) NOT NULL, "\
      "status  varchar(255) NOT NULL, "\
      "results longtext     NOT NULL"\
    ")"
  )
end

# TODO make this do things like pipe rspec output and tee it into the db somehow,
# as well as uhhhh other bookkeeping/creation things needed by pull.bash

case (cmd = ARGV[0])
when 'init' then init
else
  STDERR.puts "Bad command #{cmd.inspect}"
  exit(1)
end
