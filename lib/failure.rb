require 'mysql2'
require_relative 'db'

Db.establish_activerecord_connection

class Failure < ActiveRecord::Base
end
