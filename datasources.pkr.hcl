//datasources for Linux AMI commented for later use

# # # Data sources are always treated BEFORE locals and sources.
# data "amazon-ami" "ubuntu-22_04" {
#   access_key      = var.aws_access_key_id
#   secret_key      = var.aws_secret_access_key
#   filters = {
#     name                = format("ubuntu/images/hvm-ssd/ubuntu-*-22.04-%s-server-*", var.architecture)
#     root-device-type    = "ebs"
#     virtualization-type = "hvm"
#   }
#   most_recent = true
#   # owners      = ["326712726440"]
#   owners      = ["amazon"]
#   region      = var.aws_region
# }
data "amazon-ami" "windows-2019" {
  access_key      = var.aws_access_key_id
  secret_key      = var.aws_secret_access_key
  filters = {
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2launch-v2.html
    name                = "EC2LaunchV2-Windows_Server-2019-English-Core-Base-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

data "amazon-ami" "windows-2022" {
  access_key      = var.aws_access_key_id
  secret_key      = var.aws_secret_access_key
  filters = {
    name                = "Windows_Server-2022-English-Core-Base-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}
