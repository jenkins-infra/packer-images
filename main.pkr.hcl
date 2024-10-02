packer {
  required_version = ">= 1.7.2, < 2"
  required_plugins {
    amazon = {
      version = "1.2.2"
      source  = "github.com/hashicorp/amazon"
    }
    windows-update = {
      version = "0.16.8"
      source  = "github.com/rgl/windows-update"
    }
    azure = {
      version = "2.1.8"
      source  = "github.com/hashicorp/azure"
    }
    docker = {
      version = "1.0.10"
      source  = "github.com/hashicorp/docker"
    }
  }
}
