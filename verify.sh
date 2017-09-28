#!/bin/sh
docker-compose build
docker-compose run specs_and_deploy_pass
docker-compose run specs_fail
docker-compose run deploy_fails
