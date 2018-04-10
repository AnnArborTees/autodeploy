require 'sinatra/base'

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

    # Restarts the CI thread, forcing execution on a particular branch
    # or commit.
    post '/run/branch/:branch' do
      ci.create_thread!(branches: [params['branch']])
      "Running branch #{params['branch']}"
    end
  end

  def self.new(ci, port)
    Sinatra.new do
      instance_exec(ci, port, &WEBSERVER)
    end
  end
end
