build {
  source "docker.base" {
    name = "ubuntu"
  }

  source "amazon-ebs.base" {
    name         = "ubuntu"
    ssh_username = "ubuntu"
  }

  source "azure-arm.base" {
    name = "ubuntu"
    # List available offers and publishers with the command `az vm image list --output table`
    image_offer     = "0001-com-ubuntu-server-focal"
    image_publisher = "canonical"
    # List available SKUs with the command `az vm image list-skus --offer 0001-com-ubuntu-server-focal --location eastus --publisher canonical --output table`
    image_sku = "${local.agent_os_version_safe}-lts-gen2"
    os_type   = "Linux"
    vm_size   = local.azure_vm_size
  }

  post-processor "docker-tag" {
    only       = ["docker.ubuntu"]
    repository = "${var.docker_namespace}/${local.image_name}"
    tags       = [var.image_version, "latest"]
  }
}
