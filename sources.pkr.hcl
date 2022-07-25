# This source defines all the common settings for any AWS AMI (whatever Operating System)
source "amazon-ebs" "base" {
  ami_name      = "${local.image_name}-${var.architecture}-${local.now_unix_timestamp}"
  instance_type = local.aws_instance_type[var.architecture]

  # Define custom rootfs for build to avoid later filesystem extension during agent startups
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = local.windows_disk_size_gb
    volume_type           = "gp2"
  }

  # Where to build the VM
  region = var.aws_region

  # Where to export the AMI
  ami_regions = [
    var.aws_region
  ]

  # Egg-and-chicken: what is the base image to start from (eg. what is my egg)?
  source_ami = data.amazon-ami["${var.agent_os_type}-${local.agent_os_version_safe}"].id

  # To improve audit and garbage collecting, we provide tags
  tags = {
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
  managed_image_name                = local.image_name
  managed_image_resource_group_name = local.azure_resource_group
  async_resourcegroup_delete        = true # Faster builds, but no deletion error reporting

  # Azure API connection
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  subscription_id = var.azure_subscription_id

  # Where to build the VM
  location = "East US"

  # Where to export the image
  shared_image_gallery_destination {
    subscription        = var.azure_subscription_id
    resource_group      = local.azure_resource_group
    gallery_name        = "${var.build_type}_packer_images"
    image_name          = local.image_name
    image_version       = var.image_version
    replication_regions = lookup(local.azure_galleries, "${var.build_type}_packer_images", [])
  }

  # To improve audit and garbage collecting, we provide tags
  azure_tags = {
    imageplatform = var.architecture
    imagetype     = local.image_name
    timestamp     = local.now_unix_timestamp
    version       = var.image_version
    scm_ref       = var.scm_ref
    build_type    = var.build_type
  }
}

# This source defines all the common settings for any Azure image (whatever Operating System)
source "docker" "base" {
  image = "${var.agent_os_type}:${var.agent_os_version}"

  # Persist image on local docker engine
  commit = true

  # To improve audit and garbage collecting, we provide "labels" to the image
  changes = [
    "LABEL timestamp     = ${local.now_unix_timestamp}",
    "LABEL version       = ${var.image_version}",
    "LABEL scm_ref       = ${var.scm_ref}",
    "LABEL build_type    = ${var.build_type}",
    "ENV LANG=en_US.UTF-8",
    "ENV LANGUAGE=en_US:en",
    "ENV LC_ALL=en_US.UTF-8",
    "ENV AGENT_WORKDIR=/home/jenkins/agent",
    "WORKDIR /home/jenkins",
    "ENTRYPOINT [\"/usr/local/bin/jenkins-agent\"]",
  ]
}
