#!/usr/local/bin/ruby
load "/bundle_stub.rb"

stub_rspec do
  puts "Looks like rspec! The specs pass..."
end

stub_cap do
  puts "Capistrano fails to deploy!!"
  exit 1
end

verify do
  expect "status: deploy_failed"
  expect "Looks like rspec! The specs pass..."
  expect "Capistrano fails to deploy!!"
end
