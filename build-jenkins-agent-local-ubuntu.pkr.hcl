build {
  # Use this local source if you want to test Ansible against an existing docker image
  source "docker.test" {
    name = "local"
  }

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run tests"
    disable = true
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/packer-tests/tests /tmp/packer-tests/provisioning"
    ]
  }

  provisioner "file" {
    source      = "tests/ansible/"
    destination = "/tmp/packer-tests/tests/ansible/"
  }

  provisioner "file" {
    source      = "provisioning/tools-versions.yml"
    destination = "/tmp/packer-tests/provisioning/tools-versions.yml"
  }

  provisioner "file" {
    source      = "jdks-infos.yaml"
    destination = "/tmp/packer-tests/jdks-infos.yaml"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/packer-tests/tests/ansible",
      "/usr/local/ansible-venv/bin/ansible-playbook playbook-ubuntu.yml --inventory 'localhost,' --connection local --skip-tags windows_only"
    ]
  }
}
