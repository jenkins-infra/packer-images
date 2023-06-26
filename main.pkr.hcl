packer {
  required_version = ">= 1.7.2, < 1.10.0"
  required_plugins {
    amazon = {
      version = "1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
    windows-update = {
      version = "0.14.3"
      source  = "github.com/rgl/windows-update"
    }
    azure = {
      version = "1.4.3"
      source  = "github.com/hashicorp/azure"
    }
    docker = {
      version = "1.0.8"
      source  = "github.com/hashicorp/docker"
    }
  }
}
