require_relative 'app'
require 'open3'

class TestApp < App
  def setup_commands
    [
      %w(echo first setup command e'ef'fe'e'),
      %w(echo last setup command)
    ]
  end

  def run_tests!(run)
    run.record('echo', 'running', 'tests')

    stderr_output = ""
    run.record('ruby', '-e', %(STDERR.puts "here's some stderr output\nwhat's up")) do |line|
      stderr_output += line
    end

    run.record('echo', "FROM STDERR: ", stderr_output)
  end

  def deploy_commands
    [
      %w(echo deploying code),
      %w(echo totally deployed code)
    ]
  end
end
