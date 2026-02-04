packer {
  required_version = ">= 1.7.2, < 2"
  required_plugins {
    amazon = {
      version = "1.8.0"
      source  = "github.com/hashicorp/amazon"
    }
    windows-update = {
      version = "0.17.2"
      source  = "github.com/rgl/windows-update"
    }
    azure = {
      version = "2.5.2"
      source  = "github.com/hashicorp/azure"
    }
    docker = {
      version = "1.1.2"
      source  = "github.com/hashicorp/docker"
    }
  }
}
