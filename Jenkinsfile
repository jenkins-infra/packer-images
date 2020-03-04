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
            values 'ubuntu-18', 'windows-2019'
          }
        }
        stages {
          stage('Validate') {
            steps {
              sh 'packer validate --var-file validate-vars.json ${AGENT}-agent.json'
              sh 'packer validate --var-file validate-vars.json ${AGENT}-agent.json'
            }
          }

          stage('Build') {
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
                  --var location="East US 2" \
                  --var resource_group_name="prod-packer-images" \
                  --var subscription_id="$AZURE_SUBSCRIPTION_ID" \
                  --var client_id="$AZURE_CLIENT_ID" \
                  --var client_secret="$AZURE_CLIENT_SECRET" \
                  ${AGENT}-agent.json
              """
            }
          }
        }
      }
    }
  }
}
