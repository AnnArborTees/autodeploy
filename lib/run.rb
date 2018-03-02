require 'mysql2'
require_relative 'util'

Util.establish_activerecord_connection

class Run < ActiveRecord::Base
  after_initialize { self.status ||= 'initialized' }

  def ok?
    !status.include?('failed') && !status.include?('error')
  end

  def errored?
    status == 'error'
  end

  def record_process(options)
    output_field = options[:output_to]
    unless %w(spec_output deploy_output).include?(output_field)
      raise ArgumentError, "options[:output_to] should be either spec_output or deploy_output"
    end

    cmdline = options[:command]
    unless cmdline.is_a?(Array)
      raise ArgumentError, "options[:command] should be an array of command line arguments"
    end

    # Spin up a thread that will stream the process's stdout into the given
    # output field.
    done = false
    input_sender, send_output = output_sender_thread(output_field) { done }
    _stdin, stdout, process = Open3.popen2e(*cmdline)

    while (output = stdout.gets)
      puts output
      send_output.(output)
      yield output, send_output if block_given?
    end

    done = true
    input_sender.join
    process.value.success?
  end

  def specs_started
    update_attributes!(
      status: 'specs_started',
      specs_started_at: Time.now,
      spec_output: ''
    )
  end

  def errored(message)
    send_to_output('spec_output', message)
    update_column :status, 'error'
  end

  def send_to_output(output_field, message, client = nil)
    client ||= Run.connection

    client.query(
      "UPDATE runs SET #{output_field} = " \
      "CONCAT(#{output_field}, '#{sanitize(message, client)}') " \
      "WHERE id = #{id}"
    )
  end

  private

  def sanitize(input, client = nil)
    return '' if input.nil?

    # Escape for SQL
    client.escape(Util.color2html(input))
  end

  def output_sender_thread(output_field, &is_done)
    queue = Queue.new

    thread = Thread.new do
      loop do
        total_output = ""
        total_output += queue.pop until queue.empty?

        if total_output.empty?
          break if is_done.call
          next sleep 0.1
        end

        retries = 10
        begin
          Run.connection_pool.with_connection do |client|
            send_to_output(output_field, total_output, client)
          end

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

    [thread, queue.method(:<<)]
  end
end
