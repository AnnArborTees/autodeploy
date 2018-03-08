require 'mysql2'
require_relative 'db'

Db.establish_activerecord_connection

class Failure < ActiveRecord::Base
  belongs_to :run, inverse_of: :failures
end
