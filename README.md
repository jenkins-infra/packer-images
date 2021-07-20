# packer-images

A repository containing a number of packer build configurations for AWS & Azure.

## Requirements

* A shell (sh, bash, ash, zsh) prompt
* Packer (check template's version constraints to know which version to use)
* Define the environment variables `PKR_VAR_image_type`, `PKR_VAR_agent` and `PKR_VAR_architecture` to the target you want to build
* Configure the cloud (defined on the variable `PKR_VAR_image_type`) credentials (e.g. APi key, or Cloud's CLI access such as `az` or `aws` commands))

## Invoking the build locally

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
