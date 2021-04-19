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

def configurations = [
  'azure': [
    'ubuntu-18' : [
        'location' : 'East US 2',
        'resource_group_name' : 'prod-packer-images'
    ],
    'windows-2019' : [
        'location' : 'East US',
        'resource_group_name' : 'prod-packer-images-eastus'
    ]
  ],
  'aws': [
    'ubuntu-18' : [
        'location' : 'us-east-2',
        'resource_group_name' : ''
    ],
    'windows-2019' : [
        'location' : 'us-east-2',
        'resource_group_name' : ''
    ]
  ]
]

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
            name 'ARCHITECTURE'
            values 'amd64', 'arm64'
          }
          axis {
            name 'AGENT'
            values 'ubuntu-18', 'windows-2019'
          }
          axis {
            name 'CLOUD'
            values 'aws', 'azure'
          }
        }
        excludes {
          // Only build arm64 architecture for ubuntu on AWS
          exclude {
            axis {
              name 'ARCHITECTURE'
              values 'arm64'
            }
            axis {
              name 'CLOUD'
              values 'azure'
            }
          }
          exclude {
            axis {
              name 'ARCHITECTURE'
              values 'arm64'
            }
            axis {
              name 'AGENT'
              notValues 'ubuntu-18'
            }
            axis {
              name 'CLOUD'
              values 'aws'
            }
          }
        }
        environment {
          AZURE_SUBSCRIPTION_ID = credentials('packer-azure-subscription-id')
          AZURE_CLIENT_ID       = credentials('packer-azure-client-id')
          AZURE_CLIENT_SECRET   = credentials('packer-azure-client-secret')
          AWS_ACCESS_KEY_ID     = credentials('packer-aws-access-key-id')
          AWS_SECRET_ACCESS_KEY = credentials('packer-aws-secret-access-key')
          OPENSSH_PUBLIC_KEY    = credentials('packer-aws-openssh-public-key')
          LOCATION              = "${configurations[CLOUD][AGENT]['location']}"
          RESOURCE_GROUP_NAME   = "${configurations[CLOUD][AGENT]['resource_group_name']}"
          PACKER_HOME_DIR       = "/tmp/packer.d.${CLOUD}.${ARCHITECTURE}.${AGENT}"
          PACKER_PLUGIN_PATH    = "${PACKER_HOME_DIR}/plugins"
        }
        stages {
          stage('Validate') {
            steps {
              sh "./build.sh validateOnly"
            }
          }
          stage('Build') {
            when {
              branch 'master'
            }
            steps {
              sh "./build.sh"
            }
          }
        }
      }
    }
  }
}
