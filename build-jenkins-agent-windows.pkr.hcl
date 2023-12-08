build {
  source "azure-arm.base" {
    name         = "windows"
    communicator = "winrm"
    # List available offers and publishers with the command `az vm image list --output table`
    image_offer     = "WindowsServer"
    image_publisher = "MicrosoftWindowsServer"
    # List available SKUs with the command `az vm image list-skus --offer WindowsServer --location eastus --publisher MicrosoftWindowsServer --output table`
    image_sku       = "${var.agent_os_version}-datacenter-core-g2"
    os_type         = "Windows"
    os_disk_size_gb = local.windows_disk_size_gb
    winrm_insecure  = true
    winrm_timeout   = "20m"
    winrm_use_ssl   = true
    winrm_username  = local.windows_winrm_user[var.image_type]
  }

  ## Why repeating? https://github.com/rgl/packer-plugin-windows-update/issues/90#issuecomment-842569865
  # Note that restarts are only done when required by windows updates
  provisioner "windows-update" { pause_before = "1m" }
  provisioner "windows-update" { pause_before = "1m" }
  provisioner "windows-update" { pause_before = "1m" }

  # Installing Docker requires a restart: this first call to the installation script will prepare requirements
  provisioner "powershell" {
    pause_before      = "1m"
    environment_vars  = local.provisioning_env_vars
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password
    inline = [
      "Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/microsoft/Windows-Containers/Main/helpful_tools/Install-DockerCE/install-docker-ce.ps1' -o install-docker-ce.ps1",
      "install-docker-ce.ps1 -DockerVersion $env:DOCKER_VERSION -NoRestart -Verbose",
    ]
  }

  # Required for loading Windows Container Feature
  provisioner "windows-restart" {}

  # Install Docker-CE with Container feature loaded
  provisioner "powershell" {
    pause_before      = "1m"
    environment_vars  = local.provisioning_env_vars
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password
    inline = [
      "Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/microsoft/Windows-Containers/Main/helpful_tools/Install-DockerCE/install-docker-ce.ps1' -o install-docker-ce.ps1",
      "install-docker-ce.ps1 -DockerVersion $env:DOCKER_VERSION -Verbose",
    ]
  }

  provisioner "file" {
    pause_before = "1m"
    source       = "./provisioning/addSSHPubKey.ps1"
    destination  = "C:/"
  }

  provisioner "powershell" {
    pause_before      = "1m"
    environment_vars  = local.provisioning_env_vars
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password
    script            = "./provisioning/windows-provision.ps1"
  }

  # Recommended (and sometimes required) before running deprovisioning (sysprep)
  # ref. https:#www.packer.io/docs/builders/azure/arm#windows
  provisioner "windows-restart" {
    max_retries = 3
  }

  provisioner "file" {
    source      = "./goss/goss-windows.yaml"
    destination  = "C:/goss-windows.yaml"
  }

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run goss tests"
    disable = true
  }

  provisioner "powershell" {
    # elevated_user     = local.windows_winrm_user[var.image_type]
    # elevated_password = build.Password
    # execution_policy  = "unrestricted"
    pause_before      = "1m"
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "goss --version",
      "goss --use-alpha=1 --gossfile C:/goss-windows.yaml --loglevel DEBUG validate --retry-timeout 300s",
      "Remove-Item -Force C:/goss-windows.yaml",
    ]
  }

  # This provisioner must be the last for Azure builds, after reboots
  provisioner "powershell" {
    only              = ["azure-arm.windows"]
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm",
      "while($true) { $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $imageState.ImageState; Start-Sleep -s 10  } else { break } }"
    ]
  }
}
