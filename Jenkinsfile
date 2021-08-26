
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
    stage('Prepare') {
      steps {
        // Must be on the same agent as the packer steps
        // TODO: replace me by a custom docker image
        sh '''
        apk add --no-cache curl git
        latest_release_url="$(curl  --write-out "%{redirect_url}" --output /dev/null --silent https://github.com/jenkins-x-plugins/jx-release-version/releases/latest | sed 's#/tag/#/download/#g')"
        curl --silent --location --show-error "${latest_release_url}/jx-release-version-linux-amd64.tar.gz" \
          | tar -C /usr/local/bin -x -z -f -
        jx-release-version --version
        git fetch --tags # TODO: configure job to fetch tags automatically (migrate to infra.ci?)
        '''
      }
    }
    stage('ValidateAndBuild') {
      matrix {
        axes {
          axis {
            name 'PKR_VAR_architecture'
            values 'amd64', 'arm64'
          }
          axis {
            name 'PKR_VAR_agent'
            values 'ubuntu-20', 'windows-2019'
          }
          axis {
            name 'PKR_VAR_image_type'
            // "azure-arm" stands for "Azure Resource Manager", unrelated to arm64 CPU
            values 'amazon-ebs', 'azure-arm'
          }
        }
        excludes {
          // Do NOT build ARM images in Azure
          exclude {
            axis {
              name 'PKR_VAR_architecture'
              values 'arm64'
            }
            axis {
              name 'PKR_VAR_image_type'
              values 'azure-arm'
            }
          }
          // Only build Ubuntu images for arm64 CPU in AWS
          exclude {
            axis {
              name 'PKR_VAR_architecture'
              values 'arm64'
            }
            axis {
              name 'PKR_VAR_agent'
              notValues 'ubuntu-20'
            }
            axis {
              name 'PKR_VAR_image_type'
              values 'amazon-ebs'
            }
          }
        }
        environment {
          PKR_VAR_azure_subscription_id = credentials('packer-azure-subscription-id')
          PKR_VAR_azure_client_id       = credentials('packer-azure-client-id')
          PKR_VAR_azure_client_secret   = credentials('packer-azure-client-secret')
          AWS_ACCESS_KEY_ID             = credentials('packer-aws-access-key-id')
          AWS_SECRET_ACCESS_KEY         = credentials('packer-aws-secret-access-key')
          PACKER_HOME_DIR               = "/tmp/packer.d.${PKR_VAR_image_type}.${PKR_VAR_architecture}.${PKR_VAR_agent}"
          PACKER_PLUGIN_PATH            = "${PACKER_HOME_DIR}/plugins"
          PACKER_VARS_FILE              = ".auto.pkrvars.hcl"
        }
        stages {
          stage('Prepare') {
            stages {
              stage('Prepare on Branch Main') {
                when {
                  branch 'main'
                }
                steps {
                  sh '''
                  echo 'build_type = "staging"' >> "${PACKER_VARS_FILE}"
                  '''
                }
              }
              stage('Prepare on Tag') {
                when {
                  buildingTag()
                }
                steps {
                  sh '''
                  set -eu
                  echo 'build_type = "prod"' >> "${PACKER_VARS_FILE}"
                  echo 'image_name = "'${TAG_NAME}'"' >> "${PACKER_VARS_FILE}"
                  '''
                }
              }
              stage('Prepare and Report') {
                steps {
                  sh '''
                  echo 'scm_ref = "'"$(git rev-parse --short --verify HEAD)"'"' >> "${PACKER_VARS_FILE}"
                  packer fmt -recursive .
                  ./run-packer.sh report
                  '''
                }
              }
            }
          }
          stage('Validate') {
            steps {
              sh './run-packer.sh validate'
            }
          }
          stage('Build') {
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
