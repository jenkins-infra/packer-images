# # Data sources are always treated BEFORE locals and sources.
data "amazon-ami" "ubuntu-22_04" {
  access_key      = var.aws_access_key_id
  secret_key      = var.aws_secret_access_key
  filters = {
    name                = format("ubuntu/images/hvm-ssd/ubuntu-*-22.04-%s-server-*", var.architecture)
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  # owners      = ["326712726440"]
  owners      = ["amazon"]
  region      = var.aws_region
}
