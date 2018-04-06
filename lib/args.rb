require 'optparse'

Options = Struct.new(:app_dir, :app_type, :force, :run_once, :debug)

def parse_command_line_arguments(argv)
  result = Options.new
  result.force = false
  result.debug = false

  opts = nil
  parser = OptionParser.new do |option_parser|
    opts = option_parser
    opts.banner = "Usage: ruby ci.rb path/to/app app_type [options]"

    opts.on '-o', "--once", "Only pull once (don't loop)" do
      result.run_once = true
    end

    opts.on '-f', "--force", "Don't bother running 'git pull'" do
      result.force = true
    end

    opts.on '-d', "--debug", "Enable detailed logging to stdout" do
      result.debug = true
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

  result
end
