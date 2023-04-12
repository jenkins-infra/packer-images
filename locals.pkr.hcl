locals {
  now_unix_timestamp    = formatdate("YYYYMMDDhhmmss", timestamp())
  agent                 = format("%s-%s", var.agent_os_type, var.agent_os_version)
  agent_os_version_safe = replace(var.agent_os_version, ".", "_")
  image_name            = format("jenkins-agent-%s-%s", var.agent_os_type, var.agent_os_version)
  aws_instance_type = {
    "amd64" = "t3a.xlarge" # 4 vCPU AMD / 16 GB / $0.1504 - https://aws.amazon.com/fr/ec2/instance-types/t3/#Product_Details
    "arm64" = "t4g.xlarge" # 4 vCPU / 16 GB / $0.1344 - https://aws.amazon.com/fr/ec2/instance-types/t4/#Product_Details
  }
  # List available SKUs with the command `az vm image list-skus --offer 0001-com-ubuntu-server-jammy --location eastus --publisher canonical --output table`
  az_instance_image_sku = {
    "amd64" = "${local.agent_os_version_safe}-lts-gen2"
    "arm64" = "${local.agent_os_version_safe}-lts-arm64"
  }
  windows_winrm_user = {
    "azure-arm"  = "packer"
    "amazon-ebs" = "Administrator" # In AWS EC2, WinRM super admin must be the "Administrator" account
    "docker"     = "packer"
  }
  azure_vm_size = {
    "amd64" = "Standard_D4s_v3"  # 4 CPU / 16 GB / Huge size required to avoid https:#docs.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-troubleshoot#sysprep-timing and avoid full disk (DS2v2 only have 14 Gb SSD for system)
    "arm64" = "Standard_D4ps_v5" # 4 CPU / 16 GB / Huge size required to avoid https:#docs.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-troubleshoot#sysprep-timing and avoid full disk (DS2v2 only have 14 Gb SSD for system)
  }
  azure_destination_resource_group = "${var.build_type}-packer-images"
  azure_galleries = {
    "prod_packer_images"    = ["East US", "East US 2"]
    "staging_packer_images" = ["East US", "East US 2"] # Only the "main" branch, should map the production as much as possible
    "dev_packer_images"     = ["East US"]              # Faster builds for branches, pull requests or local development
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
