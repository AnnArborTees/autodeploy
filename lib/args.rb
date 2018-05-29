require 'optparse'

Options = Struct.new(:app_dir, :app_name, :app_type, :force, :run_once, :debug, :branches, :deploy_branch, :control_server)

def parse_command_line_arguments(argv)
  result = Options.new
  result.force = false
  result.debug = false
  result.branches = []
  result.deploy_branch = 'master'
  result.control_server = false

  opts = nil
  parser = OptionParser.new do |option_parser|
    opts = option_parser
    opts.banner = "Usage: ruby main.rb path/to/app app_type [options]"

    opts.on '-o', "--once", "Only pull once (don't loop)" do
      result.run_once = true
    end

    opts.on '-f', "--force", "Don't bother running 'git pull'" do
      result.force = true
    end

    opts.on '-d', "--debug", "Enable detailed logging to stdout" do
      result.debug = true
    end

    opts.on '-bBRANCH', "--branch BRANCH", "Add BRANCH to the list of tested branches (defaults to just master)" do |b|
      result.branches << b
    end

    opts.on '-pBRANCH', "--deploy BRANCH", "Only deploy when tests pass on BRANCH (defaults to master)" do |b|
      result.deploy_branch = b
    end

    opts.on '-s', "--control-server", "Run an HTTP server that can be used to query status and cancel runs" do
      result.control_server = true
    end

    opts.on '-nNAME', "--name NAME", "Use NAME as app name instead of project directory" do |n|
      result.app_name = n
    end

    opts.on '-h', "--help", "Print this message" do
      puts opts
      exit 0
    end
  end

  parser.parse!(argv)

  result.app_type = argv.pop
  result.app_dir = argv.pop

  if result.app_type.nil? || result.app_dir.nil?
    puts "Please specify app type and directory"
    puts opts
    exit 1
  end

  if result.app_name.nil? || result.app_name.empty?
    result.app_name = File.basename(result.app_dir)
  end

  if result.branches.empty?
    result.branches << 'master'
  end

  result
end
