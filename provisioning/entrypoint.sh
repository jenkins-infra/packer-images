#!/bin/bash

. $HOME/.asdf/asdf.sh

exec /usr/local/bin/jenkins-agent "$@"
