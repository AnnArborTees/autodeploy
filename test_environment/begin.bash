#!/bin/bash

pushd /home/autodeploy
bundle install
popd

ruby /home/autodeploy/lib/ci.rb /home/test_app test --once --debug
