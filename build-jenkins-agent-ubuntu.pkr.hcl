build {
  source "docker.base" {
    name      = "ubuntu"
    exec_user = local.ubuntu_ssh_user[var.image_type]
  }

  source "amazon-ebs.base" {
    name         = "ubuntu"
    ssh_username = local.ubuntu_ssh_user[var.image_type]
  }

  source "azure-arm.base" {
    name         = "ubuntu"
    ssh_username = local.ubuntu_ssh_user[var.image_type]
    # List available offers and publishers with the command `az vm image list --output table`
    image_offer     = "0001-com-ubuntu-server-jammy"
    image_publisher = "canonical"
    # List available SKUs with the command `az vm image list-skus --offer 0001-com-ubuntu-server-jammy --location eastus --publisher canonical --output table`
    image_sku     = local.az_instance_image_sku[var.architecture]
    image_version = try(local.images_versions["azure"][var.agent_os_type][var.agent_os_version][var.architecture], "N/A")
    os_type       = "Linux"
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

  provisioner "ansible" {
    playbook_file = "./provisioning/ansible/provision.yml"
    extra_arguments = [
      # The `@` prefix makes Ansible read the variables from a file instead of the
      # command line, so the whole tools-versions.yml is loaded as playbook variables.
      # Ref. https://developer.hashicorp.com/packer/integrations/hashicorp/ansible/latest/components/provisioner/ansible#extra_arguments
      "--extra-vars", "@${var.provision_env_file}",
    ]
    # The provisioner defaults this to the user running packer rather than the one the
    # communicator connects with, which does not exist on every builder.
    # Ref. https://developer.hashicorp.com/packer/integrations/hashicorp/ansible/latest/components/provisioner/ansible#user
    user = local.ubuntu_ssh_user[var.image_type]
  }

  provisioner "shell" {
    environment_vars = local.provisioning_env_vars
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script           = "./provisioning/ubuntu-provision.sh"
  }

  provisioner "file" {
    source      = "tests/ansible"
    destination = "/tmp/ansible-tests"
  }

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run tests"
    disable = true
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/ansible-tests",
      "sudo -u jenkins /usr/local/ansible-venv/bin/ansible-playbook playbook-linux.yml --inventory 'localhost,' --connection local"
    ]
  }

  post-processor "docker-tag" {
    only = ["docker.ubuntu"]
    # TODO specify architecture in image name with local.image_name
    repository = format("%s/jenkins-agent-%s-%s", var.docker_namespace, var.agent_os_type, var.agent_os_version)
    tags       = [var.image_version, "latest"]
  }
}
