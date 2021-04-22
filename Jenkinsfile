def buildNumber = BUILD_NUMBER as int; if (buildNumber > 1) milestone(buildNumber - 1); milestone(buildNumber) // JENKINS-43353 / JENKINS-58625

if (env.CHANGE_ID) {
  properties([
    buildDiscarder(logRotator(numToKeepStr: '10')),
  ])
} else {
  properties([
    buildDiscarder(logRotator(numToKeepStr: '96')),
 // Disable for now until we fix https://ci.jenkins.io/job/Infra/job/packer-images/job/master/148/console
 //   pipelineTriggers([[$class: "SCMTrigger", scmpoll_spec: "H/10 * * * *"]]),
  ])
}

pipeline {
  agent {
    docker {
      args '--entrypoint=""'
      image 'hashicorp/packer:1.7.2'
      label 'docker&&linux'
    }
  }
  stages {
    stage('ValidateAndBuild') {
      matrix {
        axes {
          axis {
            name 'PKR_VAR_architecture'
            values 'amd64', 'arm64'
          }
          axis {
            name 'PKR_VAR_agent'
            values 'ubuntu-18', 'windows-2019'
          }
          axis {
            name 'PKR_VAR_cloud'
            values 'aws', 'azure'
          }
        }
        excludes {
          // Only build arm64 architecture for ubuntu on AWS
          exclude {
            axis {
              name 'PKR_VAR_architecture'
              values 'arm64'
            }
            axis {
              name 'PKR_VAR_cloud'
              values 'azure'
            }
          }
          exclude {
            axis {
              name 'PKR_VAR_architecture'
              values 'arm64'
            }
            axis {
              name 'PKR_VAR_agent'
              notValues 'ubuntu-18'
            }
            axis {
              name 'PKR_VAR_cloud'
              values 'aws'
            }
          }
        }
        environment {
          PKR_VAR_subscription_id = credentials('packer-azure-subscription-id')
          PKR_VAR_client_id       = credentials('packer-azure-client-id')
          PKR_VAR_client_secret   = credentials('packer-azure-client-secret')
          AWS_ACCESS_KEY_ID       = credentials('packer-aws-access-key-id')
          AWS_SECRET_ACCESS_KEY   = credentials('packer-aws-secret-access-key')
          OPENSSH_PUBLIC_KEY      = credentials('packer-aws-openssh-public-key')
          PACKER_HOME_DIR         = "/tmp/packer.d.${PKR_VAR_cloud}.${PKR_VAR_architecture}.${PKR_VAR_agent}"
          PACKER_PLUGIN_PATH      = "${PACKER_HOME_DIR}/plugins"
        }
        stages {
          stage('Validate') {
            steps {
              sh './run-packer.sh validate'
            }
          }
          stage('Build') {
            when {
              branch 'master'
            }
            steps {
              sh './run-packer.sh build'
            }
          }
        }
      }
    }
  }
}
