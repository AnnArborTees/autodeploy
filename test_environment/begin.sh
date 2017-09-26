#!/bin/sh
docker-compose build
exec docker-compose run autodeploy
