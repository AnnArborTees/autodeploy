require_relative 'control_server'
require_relative 'ci'

require 'byebug'

ENV['RAILS_ENV'] = 'test'
ENV['SSHKIT_COLOR'] = 'true'

ci = CI.new(ARGV)
ci.create_thread!

if ci.arguments.control_server
  ControlServer.new(ci, ci.app.unique_port).run!
  ci.thread.kill if ci.thread
else
  ci.thread.join if ci.thread
end
