#!/bin/bash

. /home/jenkins/.asdg/asdf.sh

exec /usr/local/bin/jenkins-agent "$@"
