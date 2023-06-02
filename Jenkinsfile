//!/usr/bin/env groovy
//default node for pipeline and stages except for the amd/intel builds
String nodeLabel="linux-arm64-docker"

// Initialize the packer project by installing the plugins in $PACKER_HOME_DIR/ - ref. https://www.packer.io/docs/configure
// This function must be called for each distinct agent but only one time (as plugins are OS and CPU specifics)
def packerInitPlugins() {
  // Authenticating to the GitHub API with an API token (auto-generated IAT, valid for 1 hour) provided to the environment variable PACKER_GITHUB_API_TOKEN
  // to avoid hitting the rate limit. Ref. https://www.packer.io/docs/commands/init.
  withCredentials([usernamePassword(credentialsId: 'github-app-infra',usernameVariable: 'UNUSED',passwordVariable: 'PACKER_GITHUB_API_TOKEN')]) {
    // Cleanup any remnant of packer plugins on this agent
    sh 'rm -rf /home/jenkins/.config /home/jenkins/.packer*'
    sh 'packer init ./'
  }
}

if (env.BRANCH_IS_PRIMARY) {
    properties([
        buildDiscarder(logRotator(numToKeepStr: '10')),
        // Daily build is enough: only the tagged build would generate downstream PRs on jenkins-infra
        pipelineTriggers([cron('@daily')]),
        // Do not build concurently on the principal branch (to avoid Azure ARM issues with shared resources)
        disableConcurrentBuilds(),
    ])
}

if (env.CHANGE_ID) {
  properties([
    // Do not build concurently on pull requests (to avoid Azure ARM issues with shared resources), and abort previous running build
    disableConcurrentBuilds(abortPrevious: true)
  ])
}

// Define the matrix axes
Map matrix_axes = [
  cpu_architecture: ['amd64', 'arm64'],
  agent_type: ['ubuntu-22.04', 'windows-2019', 'windows-2022'],
  compute_type: ['amazon-ebs', 'azure-arm', 'docker']
]

@NonCPS
List getMatrixAxes(Map matrix_axes) {
    List axes = []
    matrix_axes.each { axis, values ->
        List axisList = []
        values.each { value ->
            axisList << [(axis): value]
        }
        axes << axisList
    }
    // calculate cartesian product
    axes.combinations()*.sum()
}
List axes = getMatrixAxes(matrix_axes).findAll { axis ->
  !(axis['cpu_architecture'] == 'amd64' && axis['compute_type'] == 'amazon-ebs') &&
  !(axis['cpu_architecture'] == 'arm64' && axis['compute_type'] == 'amazon-ebs' && axis['agent_type'] != 'ubuntu-22.04') &&
  !(axis['cpu_architecture'] == 'arm64' && axis['compute_type'] == 'azure-arm' && axis['agent_type'] != 'ubuntu-22.04') &&
  !(axis['compute_type'] == 'docker' && axis['agent_type'] == 'windows-2019') &&
  !(axis['compute_type'] == 'docker' && axis['agent_type'] == 'windows-2022')
}

// Average build time is ~50 min but windows can takes 45min of updates on AWS
timeout(time: 120, unit: 'MINUTES') {

  // main script block
  node(nodeLabel) {
    // To allow using ASDF shims
    env.PATH = "${env.PATH}:/home/jenkins/.asdf/shims:/home/jenkins/.asdf/bin"
    env.DRYRUN = "${env.BRANCH_IS_PRIMARY ? 'false' : 'true'}"

    stage('startup') {
      packerinit: {
        checkout scm
        packerInitPlugins()
      }
    }

    // Define parrallels stages
    stage('parrallels') {
      def stages = [:]

      // parallel task map
      //Map tasks = [failFast: false]

      for(int i = 0; i < axes.size(); i++) {
        // convert the Axis into valid values for withEnv step
        Map axis = axes[i]
        List axisEnv = axis.collect { k, v ->
            "${k}=${v}"
        }
        // dynamically choose node to use
        if (axis['compute_type'] == 'docker' && axis['cpu_architecture'] == 'amd64') {
          nodeLabel = "linux-amd64-docker"
        }
        stages[axisEnv.join(', ')] = { ->
          node(nodeLabel) {
            withEnv(axisEnv) {
              stage("Build ${axis['compute_type']} ${axis['agent_type']} ${axis['cpu_architecture']} image") {
                final String pkr_var_agent_os_type = agent_type.split('-')[0]
                final String pkr_var_agent_os_version = agent_type.split('-')[1]
                final String pkr_var_architecture = cpu_architecture
                final String pkr_var_image_type = compute_type
                final String pkr_var_tag_name = env.TAG_NAME
                echo nodeLabel
                echo "sh 'PACKER_LOG=1 packer validate ./'"
                ////sh 'PACKER_LOG=1 packer validate ./'
                // Execute build only for this matrix cell's setup
                retry(count: 2, conditions: [kubernetesAgent(handleNonKubernetes: true), nonresumable()]) {
                  echo "sh 'packer build -timestamp-ui -force -only="${PKR_VAR_image_type}.${PKR_VAR_agent_os_type}" ./'"
                  ////sh 'packer build -timestamp-ui -force -only="${PKR_VAR_image_type}.${PKR_VAR_agent_os_type}" ./'
                  // adding manually a cpu architecture tag to the docker image
                  if (pkr_var_image_type == 'docker') {
                    echo "docker tag jenkinsciinfra/jenkins-agent-${PKR_VAR_agent_os_type}-${PKR_VAR_agent_os_version}:latest jenkinsciinfra/jenkins-agent-${PKR_VAR_agent_os_type}-${PKR_VAR_agent_os_version}:${PKR_VAR_architecture}"
                    ////sh 'docker tag "jenkinsciinfra/jenkins-agent-${PKR_VAR_agent_os_type}-${PKR_VAR_agent_os_version}:latest" "jenkinsciinfra/jenkins-agent-${PKR_VAR_agent_os_type}-${PKR_VAR_agent_os_version}:${PKR_VAR_architecture}"'
                  }
                }
                // if docker and building a tag, push to dockerhub from inside the node
                // else we would loose the docker image
                if (pkr_var_image_type == 'docker' && pkr_var_tag_name != null) {
                  stage('Publish all tags for Docker image') {
                    echo "Pushing jenkinsciinfra/jenkins-agent-${pkr_var_agent_os_type}:${pkr_var_tag_name} & jenkinsciinfra/jenkins-agent-${pkr_var_agent_os_type}:latest for ${pkr_var_architecture}"
                    ////infra.withDockerPushCredentials {
                      ////sh 'docker push --all-tags jenkinsciinfra/jenkins-agent-${agent_type}'
                    ////}
                  }
                }
              }
            }
          }
        }
      }
      stages["updatecli"] = {
        // TODO: Implement https://github.com/jenkins-infra/pipeline-library/issues/518 to allow using the updatecli() library function
        withCredentials([
          usernamePassword(
            credentialsId: 'github-app-updatecli-on-jenkins-infra',
            usernameVariable: 'USERNAME_VALUE', // Setting this variable is mandatory, even if of not used when the credentials is a githubApp one
            passwordVariable: 'UPDATECLI_GITHUB_TOKEN'
          )
        ]) {
          sh 'updatecli version'
          sh 'updatecli diff --values ./updatecli/values.yaml --config ./updatecli/updatecli.d'
          if (env.BRANCH_IS_PRIMARY) {
            sh 'updatecli apply --values ./updatecli/values.yaml --config ./updatecli/updatecli.d'
          }
        }
      }

      stages["GC on AWS us-east-2"] = {
        env.AWS_DEFAULT_REGION    = 'us-east-2'
        withCredentials([
          string(
              credentialsId: 'packer-aws-access-key-id',
              variable: 'AWS_ACCESS_KEY_ID'
          ),
          string(
              credentialsId: 'packer-aws-secret-access-key',
              variable: 'AWS_SECRET_ACCESS_KEY'
          )
        ]) {
          catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
            sh './cleanup/aws.sh'
            sh './cleanup/aws_images.sh 1 dev'
            sh './cleanup/aws_images.sh 7 staging'
            sh './cleanup/aws_images.sh 60 prod'
            sh './cleanup/aws_snapshots.sh'
          }
        }
      }

      stages["GC on Azure"] = {
        withCredentials([
          azureServicePrincipal(
            credentialsId: 'packer-azure-serviceprincipal',
            subscriptionIdVariable: 'PACKER_AZURE_SUBSCRIPTION_ID',
            clientIdVariable: 'PACKER_AZURE_CLIENT_ID',
            clientSecretVariable: 'PACKER_AZURE_CLIENT_SECRET',
            tenantIdVariable: 'PACKER_AZURE_TENANT_ID'
          )
        ]) {
          catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
            sh 'az login --service-principal -u "$PACKER_AZURE_CLIENT_ID" -p "$PACKER_AZURE_CLIENT_SECRET" -t "$PACKER_AZURE_TENANT_ID"'
            sh 'az account set -s "$PACKER_AZURE_SUBSCRIPTION_ID"'
            sh './cleanup/azure_gallery_images.sh 1 dev'
            sh './cleanup/azure_gallery_images.sh 7 staging'
            sh './cleanup/azure.sh 1 dev'
            sh './cleanup/azure.sh 1 staging'
            sh './cleanup/azure.sh 1 prod'
          }
        }
      }

      stages["Build Docker Manifest"] = {
        if (env.TAG_NAME != null){
          // Static variable definition as this stage is outside the matrix scope
          // Improvement: pass dynamically the list of images from the matrix (e.g. use full scripted pipeline) to support other Docker agent types (such as windows-2019 or windows-2022)
          agent_type = 'ubuntu-22.04'
          infra.withDockerPushCredentials {
            sh 'docker manifest create \
                jenkinsciinfra/jenkins-agent-${agent_type}:latest \
                --amend jenkinsciinfra/jenkins-agent-${agent_type}:arm64 \
                --amend jenkinsciinfra/jenkins-agent-${agent_type}:amd64'
            sh 'docker manifest push jenkinsciinfra/jenkins-agent-"${agent_type}":latest'

            sh 'docker manifest create \
                jenkinsciinfra/jenkins-agent-${agent_type}:${TAG_NAME} \
                --amend jenkinsciinfra/jenkins-agent-${agent_type}:arm64 \
                --amend jenkinsciinfra/jenkins-agent-${agent_type}:amd64'
            sh 'docker manifest push jenkinsciinfra/jenkins-agent-"${agent_type}":"${TAG_NAME}"'
          }
        }
      }
    }
    //run
    parallel(stages)
  }
}
