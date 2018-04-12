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

    run.failures.create(output: "Wowee! This is a test failure. We'll still mark this test as 'deployed'.")
    run.failures.create(output: "Another test failure, to see how things fare with multiple failures")

    run.record('echo', "FROM STDERR: ", stderr_output)
  end

  def handle_request!(request, run, deploy_branch)
    run.record('echo', "======= GOT A REQUEST =======")
    run.record('echo', request.inspect)
  end

  def deploy_commands
    if ENV['TEST_DEPLOY_FAIL'] == 'true'
      [
        %w(echo this deploy will fail!!!),
        ['ruby', '-e', 'exit 1']
      ]
    else
      [
        %w(echo deploying code),
        %w(echo totally deployed code)
      ]
    end
  end
end
