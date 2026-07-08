build {
  # Use this local source if you want to test Ansible against an existing docker image
  source "docker.test" {
    name = "local"
  }

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run tests"
    disable = true
  }

  provisioner "ansible" {
    playbook_file   = "tests/ansible/playbook.yml"
    extra_arguments = ["--skip-tags", "windows_only"]
    ansible_env_vars = ["ANSIBLE_PIPELINING=true"]  # to prevent "[WARNING]: sftp/scp transfer mechanism failed on [127.0.0.1]"
  }
}
