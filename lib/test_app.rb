require_relative 'app'
require 'open3'

class TestApp < App
  def setup_commands
    [
      %w(echo first setup command),
      %w(echo last setup command)
    ]
  end

  def run_tests!(run)
    run.record('echo', 'running', 'tests')
  end

  def deploy_commands
    [
      %w('echo', 'deploying', 'code')
    ]
  end
end
