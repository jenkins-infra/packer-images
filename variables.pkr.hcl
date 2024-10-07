# Defines these 2 elements as "variables" instead of "locals" to allow using them in data sources
# as per https:#github.com/hashicorp/packer/issues/11011
variable "agent_os_type" {
  type        = string
  description = "Which operating system to use for this agent template build?"
}
variable "agent_os_version" {
  type        = string
  description = "Which version of the operating system 'var.agent_os_type' to use for this agent template build?"
}
variable "architecture" {
  type        = string
  description = "CPU architecture ID of the build with the following possible values: [amd64 (default), arm64]"
  default     = "amd64"
}
variable "aws_region" {
  type    = string
  default = "us-east-2"
}
variable "aws_access_key_id" {
  type    = string
  default = env("AWS_ACCESS_KEY_ID")
}
variable "aws_secret_access_key" {
  type    = string
  default = env("AWS_ACCESS_KEY_ID")
}

variable "azure_client_id" {
  type    = string
  default = env("AZURE_CLIENT_ID")
}
variable "azure_client_secret" {
  type    = string
  default = env("AZURE_CLIENT_SECRET")
}
variable "azure_subscription_id" {
  type    = string
  default = env("AZURE_SUBSCRIPTION_ID")
}
variable "azure_gallery_subscription_id" {
  type    = string
  default = env("AZURE_SUBSCRIPTION_ID") # allow to specify distinct subscription
}
variable "image_version" {
  type    = string
  default = "0.0.1" # Default is a valid version to not fail azure validation
}
variable "image_type" {
  type        = string
  description = "Which kind of Packer builder to use (e.g. cloud platform): [amazon-ebs (default), azure-arm, docker]"
  default     = "azure-arm"
}
variable "build_type" {
  type        = string
  description = "Type of build e.g. is it a development build (from a contributor machine), a ci build (pull request or branch build) or a production build (principal branch build on ci)?"
  default     = "dev" # value in ["dev", "ci", "prod"]
}
variable "scm_ref" {
  type        = string
  description = "SCM (e.g. Git...) reference of the current build. Can be a commit hash (short or long), a branch name or a tag name."
  default     = "HEAD"
}
variable "provision_env_file" {
  type        = string
  description = "Path (absolute or relative to this packer template) to the YAML file with the list of environment variables forwarded to provisioners (mainly tools versions)"
  default     = "provisioning/tools-versions.yml"
}
variable "docker_namespace" {
  type    = string
  default = "jenkinsciinfra"
}
variable "locale" {
  type    = string
  default = "en_US.UTF-8"
}
