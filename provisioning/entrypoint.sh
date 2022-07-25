#!/bin/bash

. /home/jenkins/.asdf/asdf.sh

exec /usr/local/bin/jenkins-agent "$@"
