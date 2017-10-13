#!/bin/bash

#
# Should be used like so:
#   ci.bash <path-to-app-root> [--force]
#

# Fail on error
#set -e
# Fail when the first process in a pipe fails
set -o pipefail

if [ "$1" == "" ]
then
  echo "Usage: $0 <path-to-app-root> [--force]"
  exit 2
fi

if [ "$DELAY_BETWEEN_PULLS" == "" ]
then
  export DELAY_BETWEEN_PULLS="10"
fi

RSPEC_ARGS="--format d --color"
CAP_ARGS="production deploy"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIR="$1"
APP_NAME="$(basename $DIR)"


export RAILS_ENV=test


# Outputs "commit abc123" where abc123 is the hash of the current HEAD.
function getcommit {
  git show HEAD | head -n 1
}

# Outputs "Chet McGillicutty <chet@annarbortees.com>"
function getauthor {
  git log -n 1 | ruby -e 'while g = gets; break if g.include?("Author:"); end; puts g.split(/\s/, 2).last'
}

# Outputs the full commit message
function getmessage {
  git log -n 1 | ruby -e 'while g = gets; break if g.strip.empty?; end; while g = gets; puts g; end'
}

# Runs the "db.rb" script
db="ruby $SCRIPT_DIR/lib/db.rb"


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
    git reset --hard &> /dev/null
    git pull &> /dev/null

    new_commit="$(getcommit)"
  done
  echo "New code found! HEAD is now $new_commit"
  old_commit="$new_commit"

  #
  # See if another instance has already handled this commit
  #
  if $db check-commit "$APP_NAME" "$new_commit"
  then
    echo "Beginning run for $new_commit"
  else
    echo "Run already exists for $new_commit"
    if [ "$2" != "--force" ] && [ "$2" != "--once" ]
    then
      continue
    fi
  fi


  #
  # Create a db entry for this run
  #
  run_id="$($db new-run "$APP_NAME" "master" "$new_commit" "$(getauthor)" "$(getmessage)")"

  #
  # Bundle install and migrate
  #
  if bundle install && bundle exec rake db:create db:migrate
  then
    echo "Setup complete"
  else
    $db run-errored $run_id "Failed to bundle install or migrate"
    echo "Run failed setup"
    continue
  fi


  #
  # Run rspec (pipe rspec into record-specs)
  # and deploy if it passes
  #
  echo "Running \`rspec $RSPEC_ARGS\`"

  if $db rspec-workaround $run_id $RSPEC_ARGS
  then
    echo "SPECS PASSED -- deploying now"
    $db spec-status $run_id specs_passed

    #
    # Pipe deploy script into record-deploy
    # and update status to reflect deployment result
    #
    if bundle exec cap $CAP_ARGS |& $db record-deploy $run_id
    then
      echo "DEPLOY SUCCEEDED"
      $db spec-status $run_id deployed
    else
      echo "DEPLOY FAILED"
      $db spec-status $run_id deploy_failed
    fi
  else
    echo "SPECS FAILED"
    $db spec-status $run_id specs_failed
  fi

  #
  # If this was a forced run, we probably don't want to repeatedly deploy
  #
  if [ "$2" == "--force" ] || [ "$2" == "--once" ]; then
    exit $specs_passed
  fi
done
