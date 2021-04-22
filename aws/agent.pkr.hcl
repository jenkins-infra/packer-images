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

locals {
  now_unix_timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  aws_rootfs_size_gb = 100
  aws_instance_type = {
    "amd64" = "t3.micro"  # 2 CPU / 1 GB / $0.0104
    "arm64" = "t4g.micro" # 2 CPU / 1 GB / $0.0084
  }
}

data "amazon-ami" "ubuntu-18" {

  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-${var.architecture}-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "${var.location}"
}

data "amazon-ami" "windows-2019" {
  filters = {
    name                = "Windows_Server-2019-English-Core-ContainersLatest-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = "${var.location}"
}

source "amazon-ebs" "base" {
  ami_name      = "jenkins-agent-${var.agent}-${var.architecture}-${local.now_unix_timestamp}"
  instance_type = local.aws_instance_type[var.architecture]
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = local.aws_rootfs_size_gb
    volume_type           = "gp2"
  }
  region       = var.location
  source_ami   = data.amazon-ami[var.agent].id
  ssh_username = "ubuntu"
  tags = {
    imageplatform = var.architecture
    imagetype     = "jenkins-agent-${var.agent}"
    timestamp     = local.now_unix_timestamp
  }
}

build {
  source "amazon-ebs.base" {
    name = "ubuntu-18"
  }

  provisioner "shell" {
    environment_vars = ["MAVEN_VERSION=${var.maven_version}", "COMPOSE_VERSION=${var.compose_version}"]
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    script           = "./scripts/ubuntu-18-provision.aws.${var.architecture}.sh"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}

build {
  source "amazon-ebs.base" {
    name           = "windows-2019"
    communicator   = "winrm"
    user_data_file = "./scripts/setupWinRM.ps1"
    winrm_insecure = true
    winrm_timeout  = "20m"
    winrm_use_ssl  = true
    winrm_username = "Administrator"
  }

  provisioner "windows-update" {
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    script = "./scripts/test-disk-size.ps1"
  }

  provisioner "powershell" {
    script = "./scripts/test-docker.ps1"
  }

  provisioner "powershell" {
    environment_vars = ["MAVEN_VERSION=${var.maven_version}", "GIT_VERSION=${var.git_version}", "JDK11_VERSION=${var.jdk11_version}", "JDK8_VERSION=${var.jdk8_version}", "GIT_LFS_VERSION=${var.git_lfs_version}", "OPENSSH_VERSION=${var.openssh_version}", "CLOUD_TYPE=aws", "OPENSSH_PUBLIC_KEY=${var.openssh_public_key}"]
    script           = "./scripts/windows-2019-provision.ps1"
  }

  provisioner "powershell" {
    inline = ["C:\\ProgramData\\Amazon\\EC2-Windows\\Launch\\Scripts\\InitializeInstance.ps1 -SchedulePerBoot", "C:\\ProgramData\\Amazon\\EC2-Windows\\Launch\\Scripts\\SysprepInstance.ps1 -NoShutdown"]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
