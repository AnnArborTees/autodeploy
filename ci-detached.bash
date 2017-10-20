#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function bad_args {
  echo "Usage: $0 <app root>"
  exit 1
}

app_path=$1
if [ "$app_path" == "" ]
then
  bad_args
fi

if [ "$RUBY" == "" ]
then
  RUBY="$(rvm current)"
fi

# NOTE this basename probably shouldn't have any spaces in it
name="$(basename $app_path)"

if [ "$2" == "--kill" ]
then
  tmux kill-session -t "$name"
  exit $?
else
  echo "Starting CI session with ruby version $RUBY"

  tmux kill-session -t "$name" &> /dev/null
  tmux new-session -dA -s "$name"
  tmux select-window -t "${name}:0"
  tmux split-window -h

  tmux select-pane -t 0
  tmux send-keys "cd ${app_path}"                  C-m
  tmux send-keys "alias exit='tmux detach-server'" C-m
  tmux send-keys "rvm use ${RUBY}"                 C-m

  tmux select-pane -t 1
  tmux send-keys "export DISPLAY=':0'"     C-m
  tmux send-keys "rvm use ${RUBY}"         C-m
  tmux send-keys "cd '${SCRIPT_DIR}'"      C-m
  tmux send-keys 'eval $(ssh-agent -s)'    C-m
  tmux send-keys "ssh-add ssh/*.pem"       C-m
  tmux send-keys "./ci.bash '${app_path}'" C-m

  echo "Run \`tmux a -t ${name}:0.0\` to attach."
  echo "Once attached, press Ctrl+B and then D to detach."
fi
