#!/usr/local/bin/ruby
puts "\033[0;31m*** Bundle called with args: #{ARGV}\033[0m"

if ARGV[1] == 'rspec'
  puts "Looks like rspec! Let's pretend the specs passed."
elsif ARGV[1] == 'cap'
  puts "Looks like capistrano! Let's pretend we've deployed successfully"
end
