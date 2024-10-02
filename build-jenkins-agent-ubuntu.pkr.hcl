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
    source      = "./provisioning/get-fileshare-signed-url.sh"
    destination = "/tmp/get-fileshare-signed-url.sh"
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
    source      = "./tests/goss-linux.yaml"
    destination = "/tmp/goss-linux.yaml"
  }

  provisioner "file" {
    source      = "./tests/goss-common.yaml"
    destination = "/tmp/goss-common.yaml"
  }

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run goss tests"
    disable = true
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E su - jenkins -c \"bash -eu '{{ .Path }}'\""
    environment_vars  = local.provisioning_env_vars
    inline = [
      "source /home/jenkins/.asdf/asdf.sh", # Required as this is a non-interactive and non-login `bash`
      "goss --version",
      "goss --gossfile /tmp/goss-linux.yaml --loglevel DEBUG validate",
      "goss --gossfile /tmp/goss-common.yaml --loglevel DEBUG validate",
    ]
  }

  post-processor "docker-tag" {
    only = ["docker.ubuntu"]
    # TODO specify architecture in image name with local.image_name
    repository = format("%s/jenkins-agent-%s-%s", var.docker_namespace, var.agent_os_type, var.agent_os_version)
    tags       = [var.image_version, "latest"]
  }
}
