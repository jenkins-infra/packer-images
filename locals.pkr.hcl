locals {
  now_unix_timestamp    = formatdate("YYYYMMDDhhmmss", timestamp())
  agent                 = format("%s-%s", var.agent_os_type, var.agent_os_version)
  agent_os_version_safe = replace(var.agent_os_version, ".", "_")
  image_name            = format("jenkins-agent-%s-%s-%s", var.agent_os_type, var.agent_os_version, var.architecture)
  unique_image_name     = format("%s-%s", local.image_name, local.now_unix_timestamp)

  # List available SKUs with the command `az vm image list-skus --offer 0001-com-ubuntu-server-jammy --location eastus --publisher canonical --output table`
  az_instance_image_sku = {
    "amd64" = "${local.agent_os_version_safe}-lts-gen2"
    "arm64" = "${local.agent_os_version_safe}-lts-arm64"
  }
  windows_winrm_user = {
    "azure-arm"  = "packer"
    "docker"     = "packer"
  }

  images_versions = yamldecode(file("./images-versions.yaml"))

  azure_vm_size = {
    # 4 CPU / 16 GB / Huge size required to avoid https:#docs.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-troubleshoot#sysprep-timing and avoid full disk (DS2v2 only have 14 Gb SSD for system)
    "amd64" = "Standard_D4ads_v5"
    # 4 CPU / 16 GB
    "arm64" = "Standard_D4pds_v5"
  }
  azure_destination_resource_group = "${var.build_type}-packer-images"
  azure_galleries = {
    "prod_packer_images"    = ["East US 2"]
    "staging_packer_images" = ["East US 2"]
    "dev_packer_images"     = ["East US 2"]
  }
  # Must be greater than 127 Gb to allow Azure template for Windows
  disk_size_gb = 150

  jdk_infos = yamldecode(file("jdks-infos.yaml"))

  # list of the majors jdks to install for this platform/os extracted from the jdks-infos.yaml file
  # require for bash safe iteration
  jdks = sort([
    for jdk_version in keys(local.jdk_infos[var.agent_os_type][var.architecture]) :
    replace(jdk_version, "jdk", "")
  ])
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
      "JDKS=${join(" ", local.jdks)}", # space separated for bash iteration
    ],
    flatten([
      for jdk_version, jdk_data in local.jdk_infos[var.agent_os_type][var.architecture] :
        [
          "${upper(jdk_version)}_INSTALLER_URL=${jdk_data.installer_url}",
          "${upper(jdk_version)}_CHECKSUM_VALUE=${jdk_data.checksum_value}"
        ]
    ])
  )
}
