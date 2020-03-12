if (env.CHANGE_ID) {
  properties([
    buildDiscarder(logRotator(numToKeepStr: '10')),
  ])
} else {
  properties([
    buildDiscarder(logRotator(numToKeepStr: '96')),
    pipelineTriggers([[$class: "SCMTrigger", scmpoll_spec: "H/10 * * * *"]]),
  ])
}

def azureConfigurations = [
    'ubuntu-18' : [
        'location' : 'East US 2',
        'resource_group_name' : 'prod-packer-images'
    ],
    'windows-2019' : [
        'location' : 'East US',
        'resource_group_name' : 'prod-packer-images-eastus'
    ],
    'windows-2019-docker' : [
        'location' : 'East US',
        'resource_group_name' : 'prod-packer-images-eastus'
    ]
]

def awsConfigurations = [
    'ubuntu-18' : [
        'location' : 'us-east-2'
    ],
    'windows-2019' : [
        'location' : 'us-east-2'
    ],
    'windows-2019-docker' : [
        'location' : 'us-east-2'
    ]
]

pipeline {
  agent none

  stages {
    stage('ValidateAndBuild') {
      matrix {
        agent {
          docker {
            args '--entrypoint=""'
            image 'hashicorp/packer:1.5.4'
            label 'docker&&linux'
          }
        }
        axes {
          axis {
            name 'AGENT'
            values 'ubuntu-18', 'windows-2019', 'windows-2019-docker'
          }
        }
        stages {
          parallel {
            stage('Validate Azure') {
              steps {
                sh 'packer validate --var-file validate-vars.json ./azure/${AGENT}-agent.json'
              }
            }

            stage('Validate AWS') {
              steps {
                sh 'packer validate --var-file validate-vars.json ./aws/${AGENT}-agent.json'
              }
            }
          }

          parallel {
            stage('Build Azure') {
              environment {
                AZURE_SUBSCRIPTION_ID = credentials('packer-azure-subscription-id')
                AZURE_CLIENT_ID = credentials('packer-azure-client-id')
                AZURE_CLIENT_SECRET = credentials('packer-azure-client-secret')
              }

              when {
                branch 'master'
              }

              steps {
                sh """
                    packer build \
                    --force \
                    --var location="${azureConfigurations[AGENT]['location']}" \
                    --var resource_group_name="${azureConfigurations[AGENT]['resource_group_name']}" \
                    --var subscription_id="$AZURE_SUBSCRIPTION_ID" \
                    --var client_id="$AZURE_CLIENT_ID" \
                    --var client_secret="$AZURE_CLIENT_SECRET" \
                    ./azure/${AGENT}-agent.json
                """
              }
            }

            stage('Build AWS') {
              environment {
                AWS = credentials('packer-aws')
              }

              when {
                branch 'master'
              }

              steps {
                sh """
                    packer build \
                    --force \
                    --var location="${awsConfigurations[AGENT]['location']}" \
                    --var aws_access_key="$AWS_ACCESS_KEY_ID" \
                    --var aws_secret_key="$AWS_SECRET_ACCESS_KEY" \
                    ./aws/${AGENT}-agent.json
                """
              }
            }
          }
        }
      }
    }
  }
}
