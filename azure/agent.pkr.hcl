packer {
  required_version = ">= 1.7.2, < 1.8.0"
  required_plugins {
    windows-update = {
      version = "0.12.0"
      source  = "github.com/rgl/windows-update"
    }
  }
}

variable "agent" {
  type = string
}
variable "location" {
  type = string
}
variable "compose_version" {
  type = string
}
variable "maven_version" {
  type = string
}
variable "git_lfs_version" {
  type = string
}
variable "architecture" {
  type = string
}
variable "git_version" {
  type = string
}
variable "jdk11_version" {
  type = string
}
variable "jdk8_version" {
  type = string
}
variable "openssh_public_key" {
  type = string
}
variable "openssh_version" {
  type = string
}
variable "client_id" {
  type = string
}
variable "client_secret" {
  type = string
}
variable "subscription_id" {
  type = string
}

locals {
  now_unix_timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  image_name         = "jenkins-agent-${var.agent}"
  resource_groups = {
    "East US 2" = "prod-packer-images",
    "East US"   = "prod-packer-images-eastus",
  }
}


source "azure-arm" "base" {
  azure_tags = {
    imagetype = local.image_name
    timestamp = local.now_unix_timestamp
  }
  client_id          = var.client_id
  client_secret      = var.client_secret
  location           = var.location
  managed_image_name = local.image_name
  subscription_id    = var.subscription_id
}

build {
  source "azure-arm.base" {
    name                              = "ubuntu-18"
    image_offer                       = "UbuntuServer"
    image_publisher                   = "Canonical"
    image_sku                         = "18.04-LTS"
    os_type                           = "Linux"
    managed_image_resource_group_name = local.resource_groups[var.location]
    vm_size                           = "Standard_DS2_v2"
  }

  provisioner "shell" {
    environment_vars = ["MAVEN_VERSION=${var.maven_version}", "COMPOSE_VERSION=${var.compose_version}", "ARCHITECTURE=${var.architecture}"]
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script           = "./scripts/ubuntu-18-provision.sh"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}


build {
  source "azure-arm.base" {
    name                              = "windows-2019"
    communicator                      = "winrm"
    image_offer                       = "WindowsServer"
    image_publisher                   = "MicrosoftWindowsServer"
    image_sku                         = "2019-Datacenter-Core-with-Containers"
    os_type                           = "Windows"
    managed_image_resource_group_name = local.resource_groups[var.location]
    vm_size                           = "Standard_D4_v3"
    os_disk_size_gb                   = 130
    winrm_insecure                    = true
    winrm_timeout                     = "20m"
    winrm_use_ssl                     = true
    winrm_username                    = "packer"
    async_resourcegroup_delete        = true # Faster builds, but no deletion error reporting
  }

  provisioner "windows-update" {
    max_retries = 3 # Fight against flaky Windows Updates
  }

  provisioner "windows-restart" {
    max_retries = 3 # Fight against flaky Windows Updates
  }

  provisioner "powershell" {
    script = "./scripts/test-disk-size.ps1"
  }

  provisioner "powershell" {
    script = "./scripts/test-docker.ps1"
  }

  provisioner "powershell" {
    environment_vars = ["MAVEN_VERSION=${var.maven_version}", "GIT_VERSION=${var.git_version}", "JDK11_VERSION=${var.jdk11_version}", "JDK8_VERSION=${var.jdk8_version}", "GIT_LFS_VERSION=${var.git_lfs_version}", "CLOUD_TYPE=azure"]
    script           = "./scripts/windows-2019-provision.ps1"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
