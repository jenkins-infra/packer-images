build {
  source "docker.base" {
    name = "windows"

    windows_container = true

    # https://hub.docker.com/_/microsoft-windows-servercore
    image = "mcr.microsoft.com/windows/servercore:ltsc2019"

    # To improve audit and garbage collecting, we provide "labels" to the image
    changes = [
      "LABEL timestamp     = ${local.now_unix_timestamp}",
      "LABEL version       = ${var.image_version}",
      "LABEL scm_ref       = ${var.scm_ref}",
      "LABEL build_type    = ${var.build_type}",
      "ENV LANG=${var.locale}",
      "ENV LANGUAGE=${element(split(".", var.locale), 0)}:${element(split("_", var.locale), 0)}",
      "ENV LC_ALL=${var.locale}",
      "USER jenkins",
      # https://github.com/jenkinsci/docker-agent/blob/1dd17e715fbebc7986154d5f54a0553d970dbf8d/11/windows/windowsservercore-ltsc2019/Dockerfile#L64
      "ENV AGENT_WORKDIR=C:/Users/jenkins/agent",
      # https://github.com/jenkinsci/docker-agent/blob/1dd17e715fbebc7986154d5f54a0553d970dbf8d/11/windows/windowsservercore-ltsc2019/Dockerfile#L84
      "WORKDIR C:/Users/jenkins",
      # https://github.com/jenkinsci/docker-inbound-agent/blob/708e03d72337cb6bc7debc1931ccb5019f82ecf6/11/windows/windowsservercore-ltsc2019/Dockerfile#L41
      "ENTRYPOINT [\"powershell.exe\", \"-f\", \"C:/ProgramData/Jenkins/jenkins-agent.ps1\"]",
    ]
  }

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
  provisioner "windows-update" {
    only         = ["azure-arm.windows", "azure-ebs.windows"]
    pause_before = "1m"
  }
  provisioner "windows-update" {
    only         = ["azure-arm.windows", "azure-ebs.windows"]
    pause_before = "1m"
  }
  provisioner "windows-update" {
    only         = ["azure-arm.windows", "azure-ebs.windows"]
    pause_before = "1m"
  }

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

  provisioner "powershell" {
    only             = ["docker.windows"]
    environment_vars = local.provisioning_env_vars

    # No elevated user for Docker provisioning
    script = "provisioning/windows-provision.ps1"
    # As per https://www.packer.io/docs/provisioners/powershell#execution_policy, avoid wrapping to see the exit code
    execution_policy = "none"
  }

  # Recommended (and sometimes required) before running deprovisioning (sysprep or AWS scripts)
  # ref. https:#www.packer.io/docs/builders/azure/arm#windows
  provisioner "windows-restart" {
    only        = ["azure-arm.windows", "azure-ebs.windows"]
    max_retries = 3
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
  post-processor "docker-tag" {
    only       = ["docker.windows"]
    repository = "${var.docker_namespace}/${local.image_name}"
    tags       = [var.image_version, "latest"]
  }
}
