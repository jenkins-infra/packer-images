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
    image_offer     = "0001-com-ubuntu-server-jammy"
    image_publisher = "canonical"
    # List available SKUs with the command `az vm image list-skus --offer 0001-com-ubuntu-server-jammy --location eastus --publisher canonical --output table`
    image_sku = local.az_instance_image_sku[var.architecture]
    os_type   = "Linux"
  }

  provisioner "shell" {
    only             = ["docker.ubuntu"]
    environment_vars = local.provisioning_env_vars
    script           = "./provisioning/docker-jenkins-agent.sh"
  }

  provisioner "file" {
    source      = "./provisioning/add_auth_key_to_user.sh"
    destination = "/tmp/add_auth_key_to_user.sh"
  }

  provisioner "file" {
    source      = "./gpg-keys"
    destination = "/tmp/gpg-keys"
  }

  provisioner "shell" {
    environment_vars = local.provisioning_env_vars
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script           = "./provisioning/ubuntu-provision.sh"
  }

  provisioner "file" {
    source      = "./goss/goss.yaml"
    destination = "/tmp/goss.yaml"
  }

  provisioner "shell" {
    inline = [
      "set -xeu",
      "goss --version",
      "goss --gossfile /tmp/goss.yaml validate --retry-timeout 5s",
    ]
  }

  post-processor "docker-tag" {
    only       = ["docker.ubuntu"]
    repository = "${var.docker_namespace}/${local.image_name}"
    tags       = [var.image_version, "latest"]
  }
}
