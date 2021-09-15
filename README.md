# packer-images

A repository containing a number of packer build configurations to generate Jenkins agent templates for all the Jenkins controllers
of the jenkins-infra project, such as ci.jenkins.io, infra.ci.jenkins.io, etc.

## Contributing

See the [CONTRIBUTING.md document](./CONTRIBUTING.md).

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
* can be created either manually or automatically: there are no predefined planning
* triggers a build on Jenkins that will generate artifacts tagged as `prod` (for production usage, with a lifespan of 3 month unless still used)
* indirectly triggers Pull Requests on downstream repository (through their respective `updatecli` or `dependabot` configuration) if created successfully.

Please note that the different artifacts have different versioning schemes, depending on the compute provider:

* AWS AMIs generates objects with an ID and a name, and additionally, the build type (`dev`, `staging` or `prod`) and git tag are added as metadatas
* Azure VM templates are using [Shared Image Galleries](https://docs.microsoft.com/en-us/azure/virtual-machines/shared-image-galleries) where the git tag
  maps 1:1 to a new version of an image

## Invoking the build locally

In some cases, you might want to execute the build locally (opposed to opening a Pull Request and delegate the build to the CI/CD system).

### Requirements

* A shell (sh, bash, ash, zsh) prompt
* Packer (check template's version constraints to know which version to use)
* Define the environment variables `PKR_VAR_image_type`, `PKR_VAR_agent` and `PKR_VAR_architecture` to the target you want to build
* Configure the cloud (defined on the variable `PKR_VAR_image_type`) credentials (e.g. APi key, or Cloud's CLI access such as `az` or `aws` commands))

With the requirements verified locally, execute the following command:

* Define the target to build:

```bash
# Means: "Build the ubuntu-20 agent for AWS, on ARM64 CPU
export PKR_VAR_image_type=amazon-ebs
export PKR_VAR_agent=ubuntu-20
export PKR_VAR_architecture=arm64

# Verify that you can use AWS API: the command must succeed
aws ec2 describe-instances
```

* Validate the template:

```bash
./run-packer.sh validate
```

* Validate the template:

```bash
./run-packer.sh build
```

### Azure

* Retrieve the resource group name from the source to build in the template file (directive `managed_image_resource_group_name`)
  from `*.auto.pkrvars.hcl` file associated to azure/.

* Create a new resource group on your account with this retrieved values

```bash
az group create -n myResourceGroup -l eastus
```

* Define the cloud credentials with the 3 additional variables `PKR_VAR_subscription_id`, `PKR_VAR_client_id` and `PKR_VAR_client_secret`:

```bash
PKR_VAR_subscription_id="$(az account show --query id -o tsv)"
export PKR_VAR_subscription_id

PKR_VAR_image_type=azure-arm PKR_VAR_agent=windows-2019 PKR_VAR_architecture=amd64 PKR_VAR_client_id=<client id> PKR_VAR_client_secret=<client secret> ./run-packer.sh build
```
