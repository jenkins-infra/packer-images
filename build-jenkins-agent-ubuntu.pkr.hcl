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

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run goss tests"
    disable = true
  }

  provisioner "shell" {
    inline = [
      "set -xeu",
      "goss --version",
      "goss --gossfile /tmp/goss.yaml validate --retry-timeout 5s",
    ]
  }

  post-processor "docker-tag" {
    only = ["docker.ubuntu"]
    # TODO specify architecture in image name with local.image_name
    repository = format("%s/jenkins-agent-%s-%s", var.docker_namespace, var.agent_os_type, var.agent_os_version)
    tags       = [var.image_version, "latest"]
  }
}
