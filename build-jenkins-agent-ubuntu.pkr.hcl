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

  # Docker Ubuntu image are missing required tools: let's install it as a preliminary
  provisioner "shell" {
    only             = ["docker.ubuntu"]
    environment_vars = local.provisioning_env_vars
    inline = [
      "export DEBIAN_FRONTEND=noninteractive", # Avoid APT or dpkg asking questions
      "apt-get update --quiet",
      "apt-get install --yes --no-install-recommends ca-certificates curl sudo software-properties-common",
    ]
  }

  # Retrieve agent.jar
  provisioner "shell" {
    only = ["docker.ubuntu"]
    environment_vars = concat(local.provisioning_env_vars, [
      "LANG=en_US.UTF-8",
      "LANGUAGE=en_US:en",
      "LC_ALL=en_US.UTF-8",
      "AGENT_WORKDIR=/home/jenkins/agent"
    ])
    inline = [
      "echo Retrieve agent.jar",
      "curl --create-dirs -fsSLo /usr/share/jenkins/agent.jar https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${var.remoting_version}/remoting-${var.remoting_version}.jar",
      "chmod 755 /usr/share/jenkins",
      "chmod 644 /usr/share/jenkins/agent.jar",
      "ln -sf /usr/share/jenkins/agent.jar /usr/share/jenkins/slave.jar",
      "ln -sf /usr/share/jenkins/agent.jar /usr/local/bin/jenkins-agent.jar",
    ]
  }

  # Add entrypoint script
  provisioner "file" {
    only        = ["docker.ubuntu"]
    source      = "./provisioning/entrypoint.sh"
    destination = "/usr/local/bin/entrypoint.sh"
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

  post-processors {
    post-processor "docker-tag" {
      repository = "jenkinsciinfra/${local.image_name}"
      tags       = [var.image_version]
      only       = ["docker.ubuntu"]
    }
    post-processor "docker-push" {}
  }
}
