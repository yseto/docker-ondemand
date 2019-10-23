#!/bin/bash

STATE=true
function handler {
    STATE=0
}

trap "handler" TERM

sleep 3
echo "force purge"
curl -s -X PURGE http://dondemand:5000/9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08?force=1

while $STATE
do
    sleep 5
    curl -s -X PURGE http://dondemand:5000/9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
done
