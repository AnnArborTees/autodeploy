#!/usr/local/bin/ruby
load "/bundle_stub.rb"

stub_rspec do
  puts "Looks like rspec! These specs FAIL."
  exit 1
end

stub_cap do
  puts "Looks like capistrano! How'd we get here??"
end

verify do
  expect "status: specs_failed"
  expect "Looks like rspec! These specs FAIL."
  expect "Looks like capistrano!"
end
