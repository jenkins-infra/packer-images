packer {
  required_version = ">= 1.7.2, < 2"
  required_plugins {
    amazon = { # TODO: track this version with `updatecli`
      version = "1.3.3"
      source  = "github.com/hashicorp/amazon"
    }
    windows-update = {
      version = "0.17.0"
      source  = "github.com/rgl/windows-update"
    }
    azure = {
      version = "2.4.0"
      source  = "github.com/hashicorp/azure"
    }
    docker = {
      version = "1.1.2"
      source  = "github.com/hashicorp/docker"
    }
  }
}
