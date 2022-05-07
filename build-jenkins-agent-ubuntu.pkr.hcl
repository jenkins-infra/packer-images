build {
  source "docker.base" {
    name = "ubuntu"
  }

  source "amazon-ebs.base" {
    name         = "ubuntu"
    ssh_username = "ubuntu"
  }

  source "azure-arm.base" {
    name            = "ubuntu"
    image_offer     = "0001-com-ubuntu-server-focal"
    image_publisher = "canonical"
    image_sku       = "${local.agent_os_version_safe}-lts-gen2"
    os_type         = "Linux"
    vm_size         = local.azure_vm_size
  }

  # Docker Ubuntu image are missing required tools: let's install it as a preliminary
  provisioner "shell" {
    only             = ["docker.ubuntu"]
    environment_vars = local.provisioning_env_vars
    inline = [
      "export DEBIAN_FRONTEND=noninteractive", # Avoid APT or dpkg asking questions
      "apt-get update -q",
      "apt-get install --yes --no-install-recommends ca-certificates curl sudo software-properties-common",
    ]
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
}
