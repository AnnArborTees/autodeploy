require_relative 'git'
require_relative 'db'

# We select a random delay time to decrease the chances of
# both CI machines pulling the same commit.
DELAY_BETWEEN_PULLS = (5.0...15.0)

@db = Db.new
@previous_commit = Git.commit_hash

@db.initialize_tables!

loop do
  current_commit = @previous_commit

  #
  # Pull until we have new code.
  #
  while current_commit == @previous_commit
    sleep rand(DELAY_BETWEEN_PULLS)
    Git.reset_hard!
    Git.pull!

    current_commit = Git.commit_hash
  end
  puts "New code found! HEAD is now #{current_commit}"
  @previous_commit = current_commit

  # TODO check if this commit already has a run
end
