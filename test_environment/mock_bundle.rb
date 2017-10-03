#!/usr/local/bin/ruby
load "/bundle_stub.rb"

stub_rspec do
  puts "Looks like rspec! Lets pretend the specs passed."
end

stub_cap do
  puts "Looks like capistrano! Lets pretend weve deployed successfully"
end

verify do
  expect "status: deployed"
  expect "Looks like rspec! Lets pretend the specs passed."
  expect "Looks like capistrano! Lets pretend weve deployed successfully"
end
