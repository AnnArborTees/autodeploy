require 'mysql2'
require_relative 'util'
require_relative 'failure'

Util.establish_activerecord_connection

class Run < ActiveRecord::Base
  has_many :failures, inverse_of: :run

  after_initialize { self.status ||= 'initialized' }
  after_initialize { self.spec_output ||= '' }
  after_initialize { self.deploy_output ||= '' }

  attr_accessor :current_output_field

  def ok?
    !status.include?('failed') && !status.include?('error')
  end

  def errored?
    status == 'error'
  end

  def record(*cmdline, &block)
    output_field = current_output_field
    if output_field.nil?
      raise "Set run.current_output_field = 'spec_output' or something before record_process"
    end

    unless %w(spec_output deploy_output).include?(output_field)
      raise ArgumentError, "current_output_field should be either spec_output or deploy_output"
    end

    done = false

    # These filter methods get called on output we read from stdout and stderr
    # respectively.
    stdout_filters = [
      Util.method(:color2html)
    ]
    stderr_filters = [
      Util.method(:color2html),
      Util.method(:wrap_with_error_span)
    ]

    # Spin up threads that will stream the process's stdout/stderr into the given
    # output field.
    output_sender, send_output = output_sender_thread(output_field, stdout_filters) { done }
    error_output_sender, send_error_output = output_sender_thread(output_field, stderr_filters) { done }

    semaphore = Mutex.new

    puts "#{cmdline.join(' ')}"
    Open3.popen3(*cmdline) do |_stdin, stdout, stderr, process|
      read_output_stream = lambda do |process_stream, send_output_proc, real_stream|
        lambda do
          while (output = process_stream.gets)
            real_stream.puts output
            send_output_proc.call(output)
            semaphore.synchronize { block.call(output, process_stream == stderr) } if block
          end
        end
      end

      [
        Thread.new(&read_output_stream[stdout, send_output, STDOUT]),
        Thread.new(&read_output_stream[stderr, send_error_output, STDERR])
      ].each(&:join)

      done = true
      output_sender.join
      error_output_sender.join
      process.value.success?
    end
  end
  alias record_process record

  def specs_started
    update_attributes!(
      status: 'specs_started',
      specs_started_at: Time.now
    )
  end

  def retrying_specs
    update_attributes!(
      status: 'retrying_specs',
      specs_started_at: Time.now
    )
  end

  def specs_failed
    update_attributes!(
      status: 'specs_failed',
      specs_ended_at: Time.now
    )
  end

  def deploy_started
    update_attributes!(
      status: 'deploy_started',
      specs_ended_at: Time.now,
      deploy_started_at: Time.now
    )
  end

  def deploy_failed
    update_attributes!(
      status: 'deploy_failed',
      deploy_ended_at: Time.now
    )
  end

  def deployed
    update_attributes!(
      status: 'deployed',
      deploy_ended_at: Time.now
    )
  end

  def specs_passed
    update_attributes!(
      status: 'specs_passed',
      specs_ended_at: Time.now
    )
  end

  def errored(message)
    client = Run.connection

    message = Util.color2html(message)
    message = Util.wrap_with_error_span(message)

    send_to_output_raw(message, current_output_field || 'spec_output', client) { |m| "'#{client.quote_string(m)}'" }
    update_column :status, 'error'
  end

  def send_to_output(message, output_field = nil, client = nil)
    client ||= Run.connection
    output_field ||= current_output_field

    send_to_output_raw(message, output_field, client) { |m| sanitize(m, client) }
  end

  def send_to_output_raw(message, output_field, client)
    message.chars.each_slice(10000).each do |slice|
      client.execute(
        "UPDATE runs SET #{output_field} = " \
        "CONCAT(#{output_field}, #{yield(slice.join)}) " \
        "WHERE id = #{id}"
      )
    end

    nil
  end

  private

  def sanitize(input, client = nil)
    return '' if input.nil?
    client ||= self.class.connection

    # Escape for SQL
    client.quote(Util.color2html(input))
  end

  def output_sender_thread(output_field, filters = [], &is_done)
    queue = Queue.new
    filters = Array(filters)

    thread = Thread.new do
      loop do
        total_output = ""
        total_output += queue.pop until queue.empty?

        if total_output.empty?
          break if is_done.call
          next sleep 0.1
        end

        filters.each do |filter|
          total_output = filter[total_output]
        end

        retries = 10
        begin
          Run.connection_pool.with_connection do |client|
            send_to_output_raw(total_output, output_field, client) { |m| "'#{client.quote_string(m)}'" }
          end

        rescue Mysql2::Error => e
          if retries > 0 && e.message.include?("Lost connection") || e.message.include?("server has gone away")
            retries -= 1
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
