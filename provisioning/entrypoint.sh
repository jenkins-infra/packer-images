#!/bin/bash

. $ASDF_DIR/asdf.sh

exec /usr/local/bin/jenkins-agent "$@"
