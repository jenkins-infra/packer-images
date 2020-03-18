#!/bin/bash
apt-get update
apt-get upgrade -y
apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable'
apt-get -y install docker-ce openjdk-8-jdk openjdk-11-jdk make zip
curl -L https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-Linux-x86_64 -o /usr/local/bin/docker-compose
curl https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz -o /tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz
tar zxf /tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz -C /usr/share/
ln -s /usr/share/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/bin/mvn
rm -f /tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz
mkdir -p  /mnt/agent-workspace/.m2
useradd -m -o -u 1000 -G docker jenkins
chown -R jenkins:jenkins /mnt/agent-workspace
ln -s /mnt/agent-workspace/.m2 /home/jenkins/.m2
export HISTSIZE=0 && sync

cat << EOF > /etc/cloud/cloud.cfg.d/defaults.cfg
#cloud-config
system_info:
  default_user:
    name: jenkins
    lock_passwd: True
    gecos: Jenkins
    groups: [jenkins,docker]
    shell: /bin/bash
EOF

