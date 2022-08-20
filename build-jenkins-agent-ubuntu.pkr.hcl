build {
  source "docker.base" {
    name = "ubuntu"

    # Use official ubuntu image, with the tag set to the numeric version
    image = "${var.agent_os_type}:${var.agent_os_version}"

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
      "WORKDIR /home/jenkins",
      "ENTRYPOINT [\"/usr/local/bin/jenkins-agent\"]",
      "USER jenkins",
    ]
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
    source      = "./provisioning/docker.gpg"
    destination = "/tmp/docker.gpg"
  }

  provisioner "shell" {
    environment_vars = local.provisioning_env_vars
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script           = "./provisioning/ubuntu-provision.sh"
  }

  post-processor "docker-tag" {
    only       = ["docker.ubuntu"]
    repository = "${var.docker_namespace}/${local.image_name}"
    tags       = [var.image_version, "latest"]
  }
}
