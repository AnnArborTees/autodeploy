#!/bin/bash

DELAY_BETWEEN_PULLS="10"
RSPEC_ARGS="--format d --color   spec/models/job_spec.rb" # TODO the literal file here is for testing


export RAILS_ENV=test

getcommit() {
  git show HEAD | head -n 1
  return 0
}

old_commit="$(getcommit)"
new_commit="$old_commit"

while true
do
  echo "Pulling until new code comes in... HEAD is $old_commit"

  #
  # Keep pulling until HEAD changes
  #
  while [ "$old_commit" == "$new_commit" ] && [ "$1" != "--force" ]
  do
    sleep $DELAY_BETWEEN_PULLS
    git pull &> /dev/null

    new_commit="$(getcommit)"
  done
  echo "New code found! HEAD is now $new_commit"
  old_commit="$new_commit"

  #
  # Migrate
  #
  bundle exec rake db:migrate


  # TODO perhaps create db entry for this attempt?


  #
  # Run rspec, (TODO) piped into an app that updates the db
  #
  echo "Running \`rspec $RSPEC_ARGS\`"
  bundle exec rspec $RSPEC_ARGS
  specs_passed="$?"

  if [ "$specs_passed" == "0" ]
  then
    echo "Passed!"
    # TODO deploy now
  else
    echo "SPECS FAILED"
    # TODO update that DB table
  fi


  #
  # If this was a forced run, we probably don't want to repeatedly deploy
  #
  if [ "$1" == "--force" ]; then
    exit $specs_passed
  fi
done
