locals {
  now_unix_timestamp    = formatdate("YYYYMMDDhhmmss", timestamp())
  agent                 = format("%s-%s", var.agent_os_type, var.agent_os_version)
  agent_os_version_safe = replace(var.agent_os_version, ".", "_")
  image_name            = format("jenkins-agent-%s-%s-%s", var.agent_os_type, var.agent_os_version, var.architecture)
  unique_image_name     = format("%s-%s", local.image_name, local.now_unix_timestamp)


  aws_instance_types = {
    "amd64" = "t3.xlarge"
    "arm64" = "t4g.xlarge"
  }
  # TODO: track AMI versions with `updatecli`
  # Uses aws ec2 describe-images to fetch the ami id as per the architecture
  aws_ubuntu_amis = {
    "amd64" = "ami-00eb69d236edcfaf8"
    "arm64" = "ami-039e419d24a37cb82"
  }
  # List available SKUs with the command `az vm image list-skus --offer 0001-com-ubuntu-server-jammy --location eastus --publisher canonical --output table`
  az_instance_image_sku = {
    "amd64" = "${local.agent_os_version_safe}-lts-gen2"
    "arm64" = "${local.agent_os_version_safe}-lts-arm64"
  }
  windows_winrm_user = {
    "azure-arm" = "packer"
    "docker"    = "packer"
    "amazon-ebs" = "Administrator"
  }

  # List available images `az vm image list --location eastus --publisher MicrosoftWindowsServer --offer WindowsServer --sku 2022-datacenter-core-g2 --all --output table`
  windows_image_version = yamldecode(file("${path.module}/packer-versions.yaml")).windows_image_version

  azure_vm_size = {
    "amd64" = "Standard_D4ads_v5" # 4 CPU / 16 GB / Huge size required to avoid https:#docs.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-troubleshoot#sysprep-timing and avoid full disk (DS2v2 only have 14 Gb SSD for system)
    "arm64" = "Standard_D4pds_v5" # 4 CPU / 16 GB
  }
  azure_destination_resource_group = "${var.build_type}-packer-images"
  azure_galleries = {
    "prod_packer_images"    = ["East US 2"]
    "staging_packer_images" = ["East US 2"]
    "dev_packer_images"     = ["East US 2"]
  }
  windows_disk_size_gb = 150 # Must be greater than 127 Gb to allow Azure template to work with
  provisioning_env_vars = concat(
    [for key, value in yamldecode(file(var.provision_env_file)) : "${upper(key)}=${value}"],
    [
      "CLOUD_TYPE=${var.image_type}",
      "ARCHITECTURE=${var.architecture}",
      "AGENT_OS_TYPE=${var.agent_os_type}",
      "AGENT_OS_VERSION=${var.agent_os_version}",
      "LANG=${var.locale}",
      "LANGUAGE=${element(split(".", var.locale), 0)}:C",
      "LC_ALL=${var.locale}",
    ],
  )
}
