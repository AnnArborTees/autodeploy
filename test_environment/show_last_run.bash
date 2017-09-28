#!/bin/bash
query=$@

if [ "$query" == "" ]
then
  query="*"
fi

mysql --host=database --database=autodeploy --user=root -ppw4root -e "SELECT $query FROM runs ORDER BY id desc LIMIT 1\\G"
