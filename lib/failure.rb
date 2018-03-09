require_relative 'util'

Util.establish_activerecord_connection

class Failure < ActiveRecord::Base
  belongs_to :run, inverse_of: :failures
end
