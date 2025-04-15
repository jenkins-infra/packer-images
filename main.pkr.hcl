packer {
  required_version = ">= 1.7.2, < 2"
  required_plugins {
    windows-update = {
      version = "0.16.9"
      source  = "github.com/rgl/windows-update"
    }
    azure = {
      version = "2.3.3"
      source  = "github.com/hashicorp/azure"
    }
    docker = {
      version = "1.1.1"
      source  = "github.com/hashicorp/docker"
    }
  }
}
