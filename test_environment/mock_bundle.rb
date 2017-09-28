#!/usr/local/bin/ruby
load "/bundle_stub.rb"

stub_rspec do
  puts "Looks like rspec! Let's pretend the specs passed."
end

stub_cap do
  puts "Looks like capistrano! Let's pretend we've deployed successfully"
end

verify do
  expect "status: deployed"
  expect "Looks like rspec! Let's pretend the specs passed."
  expect "Looks like capistrano! Let's pretend we've deployed successfully"
end
