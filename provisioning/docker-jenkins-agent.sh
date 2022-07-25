#!/bin/bash
# This script provision the Linux Ubuntu 20 images for Jenkins agents
# Architecture supported: amd64, arm64

set -eux -o pipefail

echo "== Setting up Remoting in the Docker image"
export DEBIAN_FRONTEND=noninteractive # Avoid APT or dpkg asking questions

# Docker Ubuntu image are missing required tools: let's install it as a preliminary
apt-get update --quiet
apt-get install --yes --no-install-recommends ca-certificates curl sudo software-properties-common

echo "= Retrieve agent.jar"
curl --create-dirs --fail --silent --show-error --location --output /usr/share/jenkins/agent.jar https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${JENKINS_REMOTING_VERSION}/remoting-${JENKINS_REMOTING_VERSION}.jar
chmod 755 /usr/share/jenkins
chmod 644 /usr/share/jenkins/agent.jar

echo "= Retrieve jenkins-agent script"
curl --create-dirs --fail --silent --show-error --location --output /usr/local/bin/jenkins-agent https://raw.githubusercontent.com/jenkinsci/docker-inbound-agent/master/jenkins-agent
chmod a+x /usr/local/bin/jenkins-agent
