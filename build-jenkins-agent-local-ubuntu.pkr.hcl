build {
  # Use this local source if you want to test Ansible against an existing docker image
  source "docker.test" {
    name = "local"
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/packer-tests/tests /tmp/packer-tests/provisioning"
    ]
  }

  provisioner "file" {
    source      = "tests/ansible/"
    destination = "/tmp/ansible-tests/"
  }

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run tests"
    disable = true
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/ansible-tests",
      "/usr/local/ansible-venv/bin/ansible-playbook playbook-linux.yml --inventory 'localhost,' --connection local"
    ]
  }
}
