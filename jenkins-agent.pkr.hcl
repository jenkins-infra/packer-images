packer {
  required_version = ">= 1.7.2, < 1.8.0"
  required_plugins {
    amazon = {
      version = "1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
    windows-update = {
      version = "0.14.0"
      source  = "github.com/rgl/windows-update"
    }
  }
}

variable "agent" {
  type        = string
  description = "Which agent to build: ubuntu-20 (default), windows-2019."
  default     = "ubuntu-20"
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
  type        = string
  description = "CPU architecure ID of the build with the following possible values: [amd64 (default), arm64]"
  default     = "amd64"
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
variable "aws_region" {
  type    = string
  default = "us-east-2"
}
variable "azure_client_id" {
  type    = string
  default = ""
}
variable "azure_client_secret" {
  type    = string
  default = ""
}
variable "azure_subscription_id" {
  default = ""
  type    = string
}
variable "image_version" {
  type    = string
  default = "0.0.1" # Default is a valid version to not fail azure validation
}
variable "image_type" {
  type        = string
  description = "Which kind of Packer builder to use (e.g. cloud platform): [amazon-ebs (default), azure-arm]"
  default     = "amazon-ebs"
}
variable "openssh_authorized_keys_url" {
  type        = string
  description = "URL to an authorized keys file to be used as default for SSH authentication of the agents"
}
variable "build_type" {
  type        = string
  description = "Type of build e.g. is it a development build (from a contributor machine), a ci build (pull request or branch build) or a production build (principal branch build on ci)?"
  default     = "dev" # value in ["dev", "ci", "prod"]
}
variable "scm_ref" {
  type        = string
  description = "SCM (e.g. Git...) reference of the current build. Can be a commit hash (short or long), a branch name or a tag name."
}

locals {
  now_unix_timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  image_name         = "jenkins-agent-${var.agent}"
  aws_instance_type = {
    "amd64" = "t3.large"  # 2 CPU / 1 GB / $0.0104
    "arm64" = "t4g.micro" # 2 CPU / 1 GB / $0.0084
  }
  windows_winrm_user = {
    "azure-arm"  = "packer"
    "amazon-ebs" = "Administrator"
  }
  azure_vm_size        = "Standard_D4s_v3" # Huge size requires - avoid https://docs.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-troubleshoot#sysprep-timing and avoid full disk (DS2v2 only have 14 Gb SSD for system)
  azure_resource_group = "${var.build_type}-packer-images"
  azure_galleries = {
    "prod_packer_images"    = ["East US", "East US 2"]
    "staging_packer_images" = ["East US", "East US 2"] # Only the "main" branch, should map the production as much as possible
    "dev_packer_images"     = ["East US"]              # Faster builds for branches, pull requests or local development
  }
}

data "amazon-ami" "ubuntu-20" {
  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-${var.architecture}-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = var.aws_region
}

data "amazon-ami" "windows-2019" {
  filters = {
    name                = "Windows_Server-2019-English-Core-ContainersLatest-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

source "amazon-ebs" "base" {
  ami_name      = "${local.image_name}-${var.architecture}-${local.now_unix_timestamp}"
  instance_type = local.aws_instance_type[var.architecture]
  # Define custom rootfs for build to avoid later filesystem extension during agent startups
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 100
    volume_type           = "gp2"
  }
  # Where to build the VM
  region = var.aws_region
  # Where to export the AMI
  ami_regions = [
    var.aws_region
  ]
  source_ami   = data.amazon-ami[var.agent].id
  ssh_username = "ubuntu"
  tags = {
    imageplatform = var.architecture
    imagetype     = local.image_name
    timestamp     = local.now_unix_timestamp
    version       = var.image_version
    scm_ref       = var.scm_ref
    build_type    = var.build_type
  }
}

source "azure-arm" "base" {
  azure_tags = {
    imageplatform = var.architecture
    imagetype     = local.image_name
    timestamp     = local.now_unix_timestamp
    version       = var.image_version
    scm_ref       = var.scm_ref
    build_type    = var.build_type
  }
  client_id                         = var.azure_client_id
  client_secret                     = var.azure_client_secret
  location                          = "East US"
  managed_image_name                = local.image_name
  subscription_id                   = var.azure_subscription_id
  managed_image_resource_group_name = local.azure_resource_group

  shared_image_gallery_destination {
    subscription        = var.azure_subscription_id
    resource_group      = local.azure_resource_group
    gallery_name        = "${var.build_type}_packer_images"
    image_name          = local.image_name
    image_version       = var.image_version
    replication_regions = lookup(local.azure_galleries, "${var.build_type}_packer_images", [])
  }
}

build {
  source "amazon-ebs.base" {
    name = "ubuntu-20"
  }

  source "azure-arm.base" {
    name            = "ubuntu-20"
    image_offer     = "0001-com-ubuntu-server-focal"
    image_publisher = "canonical"
    image_sku       = "20_04-lts-gen2"
    os_type         = "Linux"
    vm_size         = local.azure_vm_size
  }

  provisioner "file" {
    source      = "./scripts/add_auth_key_to_user.sh"
    destination = "/tmp/add_auth_key_to_user.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "MAVEN_VERSION=${var.maven_version}",
      "GIT_VERSION=${var.git_version}",
      "JDK11_VERSION=${var.jdk11_version}",
      "JDK8_VERSION=${var.jdk8_version}",
      "GIT_LFS_VERSION=${var.git_lfs_version}",
      "COMPOSE_VERSION=${var.compose_version}",
      "ARCHITECTURE=${var.architecture}",
      "CLOUD_TYPE=${var.image_type}",
      "OPENSSH_AUTHORIZED_KEYS_URL=${var.openssh_authorized_keys_url}",
    ]
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script          = "./scripts/ubuntu-20-provision.sh"
    max_retries     = 3 # Fight against APT errors
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
    winrm_username = local.windows_winrm_user[var.image_type]
  }

  source "azure-arm.base" {
    name                       = "windows-2019"
    communicator               = "winrm"
    image_offer                = "WindowsServer"
    image_publisher            = "MicrosoftWindowsServer"
    image_sku                  = "2019-Datacenter-Core-with-Containers-g2"
    vm_size                    = local.azure_vm_size
    os_type                    = "Windows"
    os_disk_size_gb            = 130
    winrm_insecure             = true
    winrm_timeout              = "20m"
    winrm_use_ssl              = true
    winrm_username             = local.windows_winrm_user[var.image_type]
    async_resourcegroup_delete = true # Faster builds, but no deletion error reporting
  }

  ## Why repeating? https://github.com/rgl/packer-plugin-windows-update/issues/90#issuecomment-842569865
  # Note that restarts are only done when required by windows updates
  provisioner "windows-update" { pause_before = "1m" }
  provisioner "windows-update" { pause_before = "1m" }
  provisioner "windows-update" { pause_before = "1m" }

  provisioner "file" {
    pause_before = "1m"
    source       = "./scripts/addSSHPubKey.ps1"
    destination  = "C:/"
  }

  provisioner "powershell" {
    environment_vars = [
      "MAVEN_VERSION=${var.maven_version}",
      "GIT_VERSION=${var.git_version}",
      "JDK11_VERSION=${var.jdk11_version}",
      "JDK8_VERSION=${var.jdk8_version}",
      "GIT_LFS_VERSION=${var.git_lfs_version}",
      "COMPOSE_VERSION=${var.compose_version}",
      "CLOUD_TYPE=${var.image_type}",
      "OPENSSH_AUTHORIZED_KEYS_URL=${var.openssh_authorized_keys_url}",
    ]
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password
    script            = "./scripts/windows-2019-provision.ps1"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
