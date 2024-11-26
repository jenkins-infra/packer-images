# This source defines all the common settings for any AWS AMI (whatever Operating System)
source "amazon-ebs" "base" {


  ami_name      = "${local.image_name}-${var.architecture}-${local.now_unix_timestamp}"
  instance_type = local.aws_instance_types[var.architecture]


  # Define custom rootfs for build to avoid later filesystem extension during agent startups
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = local.windows_disk_size_gb # TODO: check if we can rename this local to cover both windows and Ubuntu
    volume_type           = "gp2" # TODO: check if we can use `gp3` (blocker was ec2 plugin, not packer)
  }


  # Where to export the AMI
  ami_regions = [
    var.aws_destination_region
  ]


  # To improve audit and garbage collecting, we provide tags
  tags = {
    Name          = "${local.image_name}-Packer-${var.architecture}"
    imageplatform = var.architecture
    imagetype     = local.image_name
    timestamp     = local.now_unix_timestamp
    version       = var.image_version
    scm_ref       = var.scm_ref
    build_type    = var.build_type
  }
}

# This source defines all the common settings for any Azure image (whatever Operating System)
source "azure-arm" "base" {
  managed_image_resource_group_name = local.azure_destination_resource_group

  vm_size = local.azure_vm_size[var.architecture]

  # network defined in https://github.com/jenkins-infra/azure-net/blob/a396b20f676602703c0dbdf4cee977eae2669cd7/vnets.tf#L535
  virtual_network_name                = "infra-ci-jenkins-io-sponsorship-vnet"
  virtual_network_subnet_name         = "infra-ci-jenkins-io-sponsorship-vnet-packer-builds"
  virtual_network_resource_group_name = "infra-ci-jenkins-io-sponsorship"

  # Resource group where to create the VM resources (required to scope permissions into this resource group)
  build_resource_group_name = "${var.build_type}-packer-builds"

  # Azure API connection
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  subscription_id = var.azure_subscription_id

  # Where to export the image
  shared_image_gallery_destination {
    subscription   = var.azure_gallery_subscription_id
    resource_group = local.azure_destination_resource_group
    gallery_name   = "${var.build_type}_packer_images"
    # Not unique name defined in https://github.com/jenkins-infra/azure/blob/bfe56cb4f843b0c8029413090c383f7ac38dde2a/locals.tf#L4-L41
    image_name          = "${local.image_name}"
    image_version       = var.image_version
    replication_regions = lookup(local.azure_galleries, "${var.build_type}_packer_images", [])
  }

  # To improve audit and garbage collecting, we provide tags
  azure_tags = {
    imageplatform = var.architecture
    timestamp     = local.now_unix_timestamp
    version       = var.image_version
    scm_ref       = var.scm_ref
    build_type    = var.build_type
  }
}

# This source defines all the common settings for any Azure image (whatever Operating System)
source "docker" "base" {
  image = try("${var.agent_os_type}@${local.images_versions["docker"]["ubuntu"][var.agent_os_version][var.architecture]}", "N/A")

  # Persist image on local docker engine
  commit = true

  # To improve audit and garbage collecting, we provide "labels" to the image
  changes = [
    "LABEL timestamp     = ${local.now_unix_timestamp}",
    "LABEL version       = ${var.image_version}",
    "LABEL scm_ref       = ${var.scm_ref}",
    "LABEL build_type    = ${var.build_type}",
    "ENV LANG=${var.locale}",
    "ENV LANGUAGE=${element(split(".", var.locale), 0)}:${element(split("_", var.locale), 0)}",
    "ENV LC_ALL=${var.locale}",
    "ENV AGENT_WORKDIR=/home/jenkins/agent",
    "ENV PATH=/usr/local/go/bin:/home/jenkins/.asdf/shims:/home/jenkins/.asdf/bin:$${PATH}",
    "WORKDIR /home/jenkins",
    "ENTRYPOINT [\"/usr/local/bin/jenkins-agent\"]",
    "USER jenkins",
  ]
}
