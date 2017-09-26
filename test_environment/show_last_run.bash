#!/bin/bash
mysql --host=database --database=autodeploy --user=root -p -e "SELECT * FROM runs LIMIT 1;"
