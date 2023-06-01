//!/usr/bin/env groovy
//linux-arm64-docker

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

// Average build time is ~50 min but windows can takes 45min of updates on AWS
timeout(time: 120, unit: 'MINUTES')

// main script block
node('linux-arm64-docker') {
    // To allow using ASDF shims
    env.PATH = "${env.PATH}:/home/jenkins/.asdf/shims:/home/jenkins/.asdf/bin"
    env.DRYRUN = "${env.BRANCH_IS_PRIMARY ? 'false' : 'true'}"
    
    stage('startup') {
        packerinit: {
            echo "packerInitPlugins()"
        }
    }

    stage('builds') {
        def stages = [:]

        stages["updatecli"] = {
            echo "updatecli"
        }
        stages["GC"] = {
            echo "build for linux"
        }

        stages["packerbuilds"] = {
            echo "build"
        }

        parallel(stages)
    }
}
