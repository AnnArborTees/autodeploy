require 'mysql2'
require_relative 'util'
require_relative 'failure'

Util.establish_activerecord_connection

# A pending request to restart a run might look like:
#   app:    softwear-crm
#   status: pending
#   action: restart
#   target: Run#12

class Request < ActiveRecord::Base
  scope :pending, -> { where(state: 'pending').order(id: :asc) }

  def target_record
    return @target_record if @target_record

    if /Run#(?<run_id>\d+)/ =~ target
      @target_record = Run.find(run_id)
    elsif /Failure#(?<failure_id>\d+)/ =~ target
      @target_record = Failure.find(failure_id)
    end
  end

  def run
    case target_record
    when Run then target_record
    when Failure then target_record.run
    end
  end

  def failure
    case target_record
    when Run then nil
    when Failure then target_record
    end
  end

  def prepare_app!(app, branches)
    if run
      app.checkout! run.commit
    else
      app.checkout! branches.first
    end
    update_column :state, 'in_progress'
  end
end
