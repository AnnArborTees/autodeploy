#!/bin/bash

pushd /home/autodeploy
bundle install
popd

ruby -e "load '/home/autodeploy/lib/util.rb' and Util.initialize_tables!"

echo 'INSERT INTO requests (app, action, target) VALUES ("test_app", "restart", null);' | mysql --host=database --database=autodeploy --user=root -ppw4root

ruby /home/autodeploy/lib/main.rb /home/test_app test --once --debug
