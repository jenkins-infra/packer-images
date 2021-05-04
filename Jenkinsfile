
if (env.BRANCH_NAME == 'main') {
  properties([
    buildDiscarder(logRotator(numToKeepStr: '10')),
    pipelineTriggers([cron('@daily')]),
  ])
}

pipeline {
  agent {
    kubernetes {
      defaultContainer 'packer'
      yamlFile 'CiPodTemplate.yaml'
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
          axis {
            name 'PKR_VAR_location'
            values 'us-east-2', 'East US 2', 'East US'
          }
        }
        excludes {
          // Only build amazon locations on AWS
          exclude {
            axis {
              name 'PKR_VAR_cloud'
              values 'azure'
            }
            axis {
              name 'PKR_VAR_location'
              values 'us-east-2'
            }
          }
          // Only build Azure locations on Azure
          exclude {
            axis {
              name 'PKR_VAR_cloud'
              values 'aws'
            }
            axis {
              name 'PKR_VAR_location'
              values 'East US 2', 'East US'
            }
          }
          // Do NOT build ARM images in Azure
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
          // Only build Ubuntu images for ARM, in AWS
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
              branch 'main'
            }
            steps {
              sh './run-packer.sh build'
            }
          }
        }
      }
    }
    stage('Garbage Collection of Cloud Resources') {
      parallel {
        stage('Cleanup AWS us-east-2') {
          environment {
            AWS_ACCESS_KEY_ID     = credentials('packer-aws-access-key-id')
            AWS_SECRET_ACCESS_KEY = credentials('packer-aws-secret-access-key')
            AWS_REGION            = 'us-east-2'
            DRYRUN                = "${env.BRANCH_NAME == 'main' ? 'false' : 'true'}"
          }
          steps {
            container('aws') {
              sh './cleanup/aws.sh'
            }
          }
        }
      }
    }
  }
}
