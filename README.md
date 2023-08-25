# packer-images

A repository containing a number of packer build configurations to generate Jenkins agent templates for all the Jenkins controllers
of the jenkins-infra project, such as ci.jenkins.io, infra.ci.jenkins.io, etc.

## Contributing

If you have:

* Any question about this repository, please ask us on the IRC channel at #jenkins-infra or on <https://community.jenkins.io>

* A problem, a feature request or an unwanted behavior with this code or its artifacts, please open an issue on the GitHub issue tracker of this repository.

* A contribution to make, please fork the GitHub repository to your own account, create a named branch and open a Pull Request with your proposed change/fix
  * Commit messages should follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) messages
  * If your PR is not associated to an issue (JIRA, GitHub), there is not guarantee that we will read or review it: please write a message explaining the intent in this case.

## Continuous Integration/Delivery/Deployment

### Continuous Integration

Each commit or pull request of this repository is built on <https://infra.ci.jenkins.io>, a non-public Jenkins controller.

* Anyone can read the feedback from the build on the public GitHub checks + status checks of the repository.
* Unless you are an administrator, the builds must be passing.

### Continuous Delivery

Each build creates a set of artifacts (VM templates) for each cell of the build matrix (check the `Jenkinsfile_k8s` manifest) that are considered ephemeral:

1. The artifacts created by local builds (if you have the cloud credentials), Pull requests or named branch (except `main`)
  generate ephemeral artifacts tagged as `dev` with a lifespan of ~24h.
  They should never be used on production instances, they can be used for smoke testing and are not expected to be persisted.

2. The artifacts created by builds on the `main` branch are tagged as `staging` with a lifespan of 7 days.
  They can be used for validation on production instances but are not met to be persisted.

### Continuous Deployment

Releases are created by adding a tag on the repository, which:

* must follow [Semantic Versioning v2](https://semver.org/)
  * It is a constraint as we use [Azure Shared Image Galleries](https://docs.microsoft.com/en-us/azure/virtual-machines/shared-image-galleries) which requires semver.
* can be created either manually or automatically: there are no predefined planning
* triggers a build on Jenkins that will generate artifacts tagged as `prod` (for production usage, with a lifespan of 3 month unless still used)
* indirectly triggers Pull Requests on downstream repository (through their respective `updatecli` or `dependabot` configuration) if created successfully.

## Invoking the build locally

In some cases, you might want to execute the build locally (opposed to opening a Pull Request and delegate the build to the CI/CD system).

### Requirements

* A shell (sh, bash, ash, zsh) prompt
* Packer (check template's version constraints to know which version to use)
* Define the environment variables `PKR_VAR_*` to the target you want to build (hint: look at the Jenkinsfile or to the `variable` blocks in the packer template HCL files)
* Configure *all* the clouds (defined by the possible values of the variable `PKR_VAR_image_type`) credentials (e.g. API key, or clouds own CLI access such as `az` command))
* Ensure that you have a Docker Engine available

With the requirements verified locally, execute the following command:

* Define the target to build:

```bash
# Means: "Build the ubuntu-20.04 agent for Docker
export PKR_VAR_image_type=docker
export PKR_VAR_agent_os_type=ubuntu
export PKR_VAR_agent_os_version=20.04
```

* Validate the template:

```bash
packer validate ./
```

* Build only one template (example: Docker Ubuntu):

```bash
packer build -timestamp-ui -force -only="docker.ubuntu" ./
```

### Azure

* Retrieve the resource group name from the source to build in the template files (directive `managed_image_resource_group_name`).

* Create a new resource group on your account with this retrieved values

```bash
az group create -n myResourceGroup -l eastus
```

* Define the cloud credentials with the 3 additional environment variables `PKR_VAR_subscription_id`, `PKR_VAR_client_id` and `PKR_VAR_client_secret`
