local "common_goss_args" {
  expression = "--use-alpha=1 --loglevel DEBUG validate --max-concurrent=1 --retry-timeout 60s --sleep 60s --format documentation"
}

build {
  source "amazon-ebs.base" {
    name           = "windows"
    communicator   = "winrm"
    user_data_file = "./provisioning/setupWinRM.ps1"
    winrm_insecure = true
    winrm_timeout  = "20m"
    winrm_use_ssl  = true
    winrm_username = local.windows_winrm_user[var.image_type]

    fast_launch {
      enable_fast_launch = true
    }
  }
  source "azure-arm.base" {
    name         = "windows"
    communicator = "winrm"
    # List available offers and publishers with the command `az vm image list --publisher MicrosoftWindowsServer --all --output table`
    # Warnings: take quite some time; "windowsserver2022" not listed
    image_offer     = var.agent_os_version == "2022" ? "windowsserver2022" : "WindowsServer"
    image_publisher = "MicrosoftWindowsServer"
    # List available SKUs with the command `az vm image list-skus --offer WindowsServer --location eastus --publisher MicrosoftWindowsServer --output table`
    # For Windows version 2022, you'll have to use `--offer windowsserver2022` (cf https://github.com/jenkins-infra/helpdesk/issues/5142)
    image_sku       = "${var.agent_os_version}-datacenter-core-g2"
    image_version   = try(local.images_versions["azure"]["windows"][var.agent_os_version][var.architecture], "N/A")
    os_type         = "Windows"
    os_disk_size_gb = local.disk_size_gb
    winrm_insecure  = true
    winrm_timeout   = "20m"
    winrm_use_ssl   = true
    winrm_username  = local.windows_winrm_user[var.image_type]
  }

  provisioner "windows-update" {
    only         = local.skip_on_pr_except_for_2019 ? ["skipped-on-pr"] : ["amazon-ebs.windows", "azure-arm.windows"]
    filters = [
      # exclude KB5007651:
      #   Update for Windows Security platform - KB5007651 (Version 10.0.29510.1001)
      # NB it can only be applied while the user is logged in.
      "exclude:$_.Title -like '*KB5007651*'",
      # Ref. https://github.com/jenkins-infra/packer-images/issues/2915
      "exclude:$_.Title -like '*KB5099538*'",
      "include:$true",
    ]
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
    # Previous provisioner might restart
    pause_before = "1m"
    source       = "./provisioning/addSSHPubKey.ps1"
    destination  = "C:/"
  }

  provisioner "file" {
    source      = "./provisioning/visualstudio.vsconfig"
    destination = "C:/"
  }

  provisioner "powershell" {
    environment_vars  = local.provisioning_env_vars
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password
    script            = "./provisioning/windows-provision.ps1"
  }

  # Recommended (and sometimes required) before running deprovisioning (sysprep)
  # ref. https:#www.packer.io/docs/builders/azure/arm#windows
  # Note: skipped on pull requests
  provisioner "windows-restart" {
    # TODO: might be needed when reactivating Windows tests
    only        = local.skip_on_pr ? ["skipped-on-pr"] : ["amazon-ebs.windows", "azure-arm.windows"]
    max_retries = 3
    # Previous provisioner might restart
    pause_before = "1m"
  }

  #provisioner "file" {
  #  source      = "./tests/goss-windows-2019.yaml"
  #  destination = "C:/goss-windows-2019.yaml"
  #}

  #provisioner "file" {
  #  source      = "./tests/goss-windows.yaml"
  #  destination = "C:/goss-windows.yaml"
  #}

  #provisioner "file" {
  #  source      = "./tests/goss-common.yaml"
  #  destination = "C:/goss-common.yaml"
  #}

  provisioner "breakpoint" {
    note    = "Enable this breakpoint to pause before trying to run goss tests"
    disable = true
  }

  # Sanity check for PowerShell: ensure that pwsh is present
  provisioner "powershell" {
    inline = [
      "pwsh --version",
    ]
  }

  #provisioner "powershell" {
  #  max_retries      = 2
  #  environment_vars = local.provisioning_env_vars
  #  inline = [
  #    "goss --version",
  #    "$ErrorActionPreference = 'SilentlyContinue'",
  #    "if (Test-Path C:/goss-windows-${var.agent_os_version}.yaml) { goss --gossfile C:/goss-windows-${var.agent_os_version}.yaml ${local.common_goss_args} } else { Write-Host 'INFO: no dedicated Windows ${var.agent_os_version} goss file'}",
  #    "$ErrorActionPreference = 'Stop'",
  #    "goss --gossfile C:/goss-windows.yaml ${local.common_goss_args}",
  #    "goss --gossfile C:/goss-common.yaml ${local.common_goss_args}",
  #    "Remove-Item -Force C:/goss-windows.yaml",
  #    "Remove-Item -Force C:/goss-common.yaml",
  #    "Remove-Item -Force C:/visualstudio.vsconfig",
  #  ]
  #}

  # This provisioner must be the last for Azure builds, after reboots
  # Note: skipped on pull requests
  provisioner "powershell" {
    only              = local.skip_on_pr ? ["skipped-on-pr"] : ["azure-arm.windows"]
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm",
      "while($true) { $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $imageState.ImageState; Start-Sleep -s 10  } else { break } }"
    ]
  }

  # This provisioner must be the last for AWS EBS builds, after reboots
  # Note: skipped on pull requests
  provisioner "powershell" {
    only              = local.skip_on_pr ? ["skipped-on-pr"] : ["amazon-ebs.windows"]
    elevated_user     = local.windows_winrm_user[var.image_type]
    elevated_password = build.Password

    inline = [
      "& \"$env:ProgramFiles/amazon/ec2launch/ec2launch.exe\" sysprep",
    ]
  }
}
