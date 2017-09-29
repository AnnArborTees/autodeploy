#!/bin/bash

service="$1"
if [ "$service" == "" ]
then
  service=interactive
fi

docker-compose build $service
exec docker-compose run $service bash
