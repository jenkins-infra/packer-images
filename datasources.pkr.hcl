# Data sources are always treated BEFORE locals and sources.
data "amazon-ami" "ubuntu-22_04" {
  filters = {
    name                = format("ubuntu/images/hvm-ssd/ubuntu-*-22.04-%s-server-*", var.architecture)
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = var.aws_region
}

data "amazon-ami" "windows-2019" {
  filters = {
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2launch-v2.html
    name                = "EC2LaunchV2-Windows_Server-2019-English-Full-ContainersLatest-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

data "amazon-ami" "windows-2022" {
  filters = {
    name                = "Windows_Server-2022-English-Full-ContainersLatest-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}
