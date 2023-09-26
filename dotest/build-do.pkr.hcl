variable "doctl_token" {
  type    = string
  default = env("DOCTL_TOKEN")
}

variable "provision_env_file" {
  type        = string
  description = "Path (absolute or relative to this packer template) to the YAML file with the list of environment variables forwarded to provisioners (mainly tools versions)"
  default     = "../provisioning/tools-versions.yml"
}
variable "image_type" {
  type        = string
  description = "Which kind of Packer builder to use (e.g. cloud platform): [amazon-ebs (default), azure-arm, docker]"
  default     = "amazon-ebs"
}
variable "architecture" {
  type        = string
  description = "CPU architecture ID of the build with the following possible values: [amd64 (default), arm64]"
  default     = "amd64"
}
variable "agent_os_type" {
  type        = string
  description = "Which operating system to use for this agent template build?"
}
variable "agent_os_version" {
  type        = string
  description = "Which version of the operating system 'var.agent_os_type' to use for this agent template build?"
}
variable "locale" {
  type    = string
  default = "en_US.UTF-8"
}
locals {
  provisioning_env_vars = concat(
    [for key, value in yamldecode(file(var.provision_env_file)) : "${upper(key)}=${value}"],
    [
      "CLOUD_TYPE=${var.image_type}",
      "ARCHITECTURE=${var.architecture}",
      "AGENT_OS_TYPE=${var.agent_os_type}",
      "AGENT_OS_VERSION=${var.agent_os_version}",
      "LANG=${var.locale}",
      "LANGUAGE=${element(split(".", var.locale), 0)}:C",
      "LC_ALL=${var.locale}",
    ],
  )
}

source "digitalocean" "amd64" {
  api_token    = "${var.doctl_token}"
  image        = "ubuntu-22-04-x64"
  region       = "nyc3"
  size         = "s-1vcpu-1gb"
  ssh_username = "root"
  user_data_file = "./user-data"
}

build {
  sources = ["source.digitalocean.amd64"]

  provisioner "file" {
    source      = "../provisioning/add_auth_key_to_user.sh"
    destination = "/tmp/add_auth_key_to_user.sh"
  }

  provisioner "file" {
    source      = "../gpg-keys"
    destination = "/tmp/gpg-keys"
  }

  provisioner "shell" {
    environment_vars = local.provisioning_env_vars
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script           = "../provisioning/ubuntu-provision.sh"
  }

  provisioner "file" {
    source      = "../goss/goss.yaml"
    destination = "/tmp/goss.yaml"
  }

  provisioner "shell" {
    inline = [
      "set -xeu",
      "goss --version",
      "goss --gossfile /tmp/goss.yaml validate --retry-timeout 5s",
    ]
  }
}
