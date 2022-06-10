# Data sources are always treated BEFORE locals and sources.
data "amazon-ami" "ubuntu-20_04" {
  filters = {
    name                = format("ubuntu/images/hvm-ssd/ubuntu-*-20.04-%s-server-*", var.architecture)
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = var.aws_region
}

data "amazon-ami" "windows-2019" {
  filters = {
    # Pinned to 20220511 version because of https://github.com/jenkins-infra/packer-images/issues/253
    # TODO: unpin once 202206* is released on AWS and proven fixed
    name                = "Windows_Server-2019-English-Core-ContainersLatest-2022.05.11*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

data "amazon-ami" "windows-2022" {
  filters = {
    name                = "Windows_Server-2022-English-Core-ContainersLatest-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}
