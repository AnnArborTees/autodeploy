require 'sinatra/base'

# This is a sinatra server that lets you query the current
# status of execution and cancel the current operation.
#
# In the future, this could be upgraded to stream spec output
# to the browser in real-time.
#
# As of the time of writing, the aatci web interface does not
# utilize this ControlServer in any way, so it's not used.

class ControlServer
  WEBSERVER = lambda do |ci, port|
    set :port, port

    get '/' do
      ci.status
    end

    get '/status' do
      ci.status
    end

    # Cancels the current operation (restarts the CI thread)
    post '/cancel' do
      ci.create_thread!
      "Stopped currently running process"
    end
  end

  def self.new(ci, port)
    Sinatra.new do
      instance_exec(ci, port, &WEBSERVER)
    end
  end
end
