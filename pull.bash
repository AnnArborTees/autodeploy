#!/bin/bash

#
# Should be used like so:
#   pull.bash <path-to-app-root> [--force]
#

set -e #=================FAIL ON ERROR=================

if [ "$1" == "" ]
then
  echo "Usage: pull.bash <path-to-app-root> [--force]"
  exit 2
fi

if [ "$DELAY_BETWEEN_PULLS" == "" ]
then
  export DELAY_BETWEEN_PULLS="10"
fi
RSPEC_ARGS="--format d --color   spec/models/job_spec.rb" # TODO the literal file here is for testing
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIR="$1"
APP_NAME="$(basename $DIR)"


export RAILS_ENV=test


# Outputs "commit abc123" where abc123 is the hash of the current HEAD.
function getcommit {
  git show HEAD | head -n 1
}

# Runs the "db.rb" script
db="ruby $SCRIPT_DIR/db.rb"


#
# Change current working directory to the app root
# and get ready to loop forever
#
pushd $DIR > /dev/null
function on-done {
  popd > /dev/null
}
trap on-done EXIT

old_commit="$(getcommit)"
new_commit="$old_commit"

$db init

while true
do

  echo ""
  echo "========================================================="
  echo "Pulling until new code comes in... HEAD is $old_commit"
  echo "---"

  #
  # Keep pulling until HEAD changes
  #
  while [ "$old_commit" == "$new_commit" ] && [ "$2" != "--force" ]
  do
    sleep $DELAY_BETWEEN_PULLS
    git pull &> /dev/null

    new_commit="$(getcommit)"
  done
  echo "New code found! HEAD is now $new_commit"
  old_commit="$new_commit"

  #
  # Create a db entry
  #
  run_id="$($db new-run "$APP_NAME" "master")"

  #
  # Bundle install and migrate
  #
  if bundle install && bundle exec rake db:migrate
  then
    echo "Setup complete"
  else
    $db run-errored $run_id "Failed to bundle install or migrate"
    echo "Run failed setup"
    continue
  fi



  #
  # Run rspec
  #
  echo "Running \`rspec $RSPEC_ARGS\`"

  bundle exec rspec $RSPEC_ARGS | $db record-specs $run_id
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
