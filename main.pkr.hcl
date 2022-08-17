packer {
  required_version = ">= 1.7.2, < 1.9.0"
  required_plugins {
    amazon = {
      version = "1.1.2"
      source  = "github.com/hashicorp/amazon"
    }
    windows-update = {
      version = "0.14.1"
      source  = "github.com/rgl/windows-update"
    }
    azure = {
      version = "1.3.0"
      source  = "github.com/hashicorp/azure"
    }
    docker = {
      version = "1.0.8"
      source  = "github.com/hashicorp/docker"
    }
  }
}
