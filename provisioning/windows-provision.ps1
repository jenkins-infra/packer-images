## Fail fast - equivalent of "set -e"
$ErrorActionPreference = 'Stop'

## Uncomment to enable Verbose mode - equivalent of "set -x"
# https://stackoverflow.com/questions/41324882/how-to-run-a-powershell-script-with-verbose-output
# $VerbosePreference="Continue"
# Set-PSDebug -Trace 1

## Enable unprivileged actions for this script
# See https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force

## Load Powershell libraries
Add-Type -AssemblyName System.Web
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


## Reusable Functions (must be declared before calling)
Function Retry-Command {
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position=1, Mandatory=$false)]
        [int]$Maximum = 5,

        [Parameter(Position=2, Mandatory=$false)]
        [int]$Delay = 100
    )

    Begin {
        $cnt = 0
    }

    Process {
        do {
            $cnt++
            try {
                $ScriptBlock.Invoke()
                return
            } catch {
                Write-Error $_.Exception.InnerException.Message -ErrorAction Continue
                Start-Sleep -Milliseconds $Delay
            }
        } while ($cnt -lt $Maximum)

        # Throw an error after $Maximum unsuccessful invocations. Doesn't need
        # a condition, since the function returns upon successful invocation.
        throw 'Execution failed.'
    }
}

Function DownloadFile($url, $targetFile) {
    Write-Host "Downloading $url"
    Retry-Command -ScriptBlock {
        $ProgressPreference = 'SilentlyContinue' # Disable Progress bar for faster downloads
        Invoke-WebRequest $url -OutFile $targetFile
    }
}

Function AddToPathEnv($path) {
    $oldPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
    $newPath = '{0};{1}' -f $path,$oldPath
    Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value $newPath | Out-Null
}

# Install OpenSSH (from Windows Features)
Write-Output "= Installing OpenSSH Server..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Write-Output "= Setting up OpenSSH Server..."
Set-Service -Name sshd -StartupType 'Automatic'
Write-Output "= Starting OpenSSH Server..."
Start-Service sshd
Write-Output "= Adding OpenSSH to the Firewall..."
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null

# Prepare Tools Installation
$baseDir = 'C:\tools'
New-Item -ItemType Directory -Path $baseDir -Force | Out-Null

# Ensure NuGet package provider is initialized (non-interactively)
Get-PackageProvider NuGet -ForceBootstrap

## List of tools to use
$downloads = [ordered]@{
    'jdk11' = @{
        'url' = 'https://github.com/adoptium/temurin11-binaries/releases/download/jdk-{0}/OpenJDK11U-jdk_x64_windows_hotspot_{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JDK11_VERSION),$env:JDK11_VERSION.Replace('+', '_');
        'local' = "$baseDir\temurin11.zip";
        'expandTo' = $baseDir;
        'postExpand' = {
            & Move-Item -Path "$baseDir\jdk-11*" -Destination "$baseDir\jdk-11"
        };
        'cleanupLocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-11\bin\java.exe" -version;
        }
    };
    'jdk17' = @{
        'url' = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-{0}/OpenJDK17U-jdk_x64_windows_hotspot_{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JDK17_VERSION),$env:JDK17_VERSION.Replace('+', '_');
        'local' = "$baseDir\temurin17.zip";
        'expandTo' = $baseDir;
        'postExpand' = {
            & Move-Item -Path "$baseDir\jdk-17*" -Destination "$baseDir\jdk-17"
        };
        'cleanupLocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-17\bin\java.exe" -version;
        }
    };
    'jdk19' = @{
        'url' = 'https://github.com/adoptium/temurin19-binaries/releases/download/jdk-{0}/OpenJDK19U-jdk_x64_windows_hotspot_{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JDK19_VERSION),$env:JDK19_VERSION.Replace('+', '_');
        'local' = "$baseDir\temurin19.zip";
        'expandTo' = $baseDir;
        'postExpand' = {
            & Move-Item -Path "$baseDir\jdk-19*" -Destination "$baseDir\jdk-19"
        };
        'cleanupLocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-19\bin\java.exe" -version;
        }
    };
    'jdk21' = @{
        'url' = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-{0}/OpenJDK21U-jdk_x64_windows_hotspot_ea_21-0-{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JDK21_VERSION),$env:JDK21_VERSION.Split('[+-]')[1];
        'local' = "$baseDir\temurin21.zip";
        'expandTo' = $baseDir;
        'postExpand' = {
            & Move-Item -Path "$baseDir\jdk-21*" -Destination "$baseDir\jdk-21"
        };
        'cleanupLocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-21\bin\java.exe" -version;
        }
    };
    'jdk8' = @{
        'url' = 'https://github.com/adoptium/temurin8-binaries/releases/download/jdk{0}/OpenJDK8U-jdk_x64_windows_hotspot_{1}.zip' -f $env:JDK8_VERSION,$env:JDK8_VERSION.Replace('-', '');
        'local' = "$baseDir\temurin8.zip";
        'expandTo' = $baseDir;
        'postExpand' = {
            & Move-Item -Path "$baseDir\jdk8*" -Destination "$baseDir\jdk-8"
        };
        'cleanupLocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-8\bin\java.exe" -version;
        }
    }
    'maven' = @{
        'url' = 'https://archive.apache.org/dist/maven/maven-3/{0}/binaries/apache-maven-{0}-bin.zip' -f $env:MAVEN_VERSION;
        'local' = "$baseDir\maven.zip";
        'expandTo' = $baseDir;
        'path' = '{0}\apache-maven-{1}\bin' -f $baseDir,$env:MAVEN_VERSION;
        'env' = @{
            'MAVEN_HOME' = '{0}\apache-maven-{1}' -f $baseDir,$env:MAVEN_VERSION;
        };
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & "mvn.cmd" -v;
        }
    };
    'git' = @{
        'url' = 'https://github.com/git-for-windows/git/releases/download/v{0}.windows.1/MinGit-{0}-64-bit.zip' -f $env:GIT_WINDOWS_VERSION;
        'local' = "$baseDir\MinGit.zip";
        'expandTo' = "$baseDir\git";
        'postExpand' = {
            & "$baseDir\git\cmd\git.exe" config --system core.autocrlf false;
            & "$baseDir\git\cmd\git.exe" config --system core.longpaths true;
        };
        # git cmd and gnu tools included with git as paths
        'path' = "$baseDir\git\cmd;$baseDir\git\usr\bin";
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & "git.exe" --version;
        }
    };
    'gitlfs' = @{
        'url' = 'https://github.com/git-lfs/git-lfs/releases/download/v{0}/git-lfs-windows-amd64-v{0}.zip' -f $env:GIT_LFS_VERSION;
        'local' = "$baseDir\GitLfs.zip";
        'expandTo' = "$baseDir";
        'postExpand' = {
            #There is a 1st-level directory in the archive since git-lfs 3.2.0
            & Move-Item -Path "$baseDir\git-lfs-$env:GIT_LFS_VERSION\*" -Destination "$baseDir\git\mingw64\bin";
            & Remove-Item -Force -Recurse "$baseDir\git-lfs-$env:GIT_LFS_VERSION";
            & "$baseDir\git\cmd\git.exe" lfs install;
        };
        'path' = "$baseDir\git\mingw64\bin";
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & "git-lfs.exe" version;
        }
    };
    'dockercompose' = @{
        'url' = 'https://github.com/docker/compose/releases/download/v{0}/docker-compose-Windows-x86_64.exe' -f $env:COMPOSE_VERSION;
        'local' = "$baseDir\docker-compose.exe"
        'sanityCheck'= {
            & "docker-compose.exe" -v;
        }
    };
    'hadolint' = @{
        'url' = 'https://github.com/hadolint/hadolint/releases/download/v{0}/hadolint-Windows-x86_64.exe' -f $env:HADOLINT_VERSION;
        'local' = "$baseDir\hadolint.exe"
        'sanityCheck'= {
            & "hadolint.exe" --version;
        }
    };
    'cst' = @{
        'url' = 'https://github.com/GoogleContainerTools/container-structure-test/releases/download/v{0}/container-structure-test-windows-amd64.exe' -f $env:CST_VERSION;
        'local' = "$baseDir\container-structure-test.exe"
        'sanityCheck'= {
            & "container-structure-test.exe" version;
        }
    };
    'jx-release-version' = @{
        'url' = 'https://github.com/jenkins-x-plugins/jx-release-version/releases/download/v{0}/jx-release-version-windows-amd64.zip' -f $env:JXRELEASEVERSION_VERSION;
        'local' = "$baseDir\jx-release-version.zip"
        'expandTo' = $baseDir;
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & "jx-release-version.exe" -version;
        }
    };
    'jq' = @{
        'url' = 'https://github.com/stedolan/jq/releases/download/jq-{0}/jq-win64.exe'  -f $env:JQ_VERSION;
        'local' = "$baseDir\jq.exe"
        'sanityCheck'= {
            & jq.exe --version;
        }
    };
    'az' = @{
        'url' = 'https://azcliprod.blob.core.windows.net/msi/azure-cli-{0}.msi' -f $env:AZURECLI_VERSION;
        'local' = "$baseDir\AzureCLI.msi";
        'postExpand' = {
            ## Add these options to msiexec.exe to write debug to the log file
            # /L*V "C:\package.log"
            Start-Process msiexec.exe -Wait -ArgumentList "/i $baseDir\AzureCLI.msi /quiet /L*V C:\package.log";
        };
        'cleanupLocal' = 'true';
        'path' = 'C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\';
        'sanityCheck'= {
            & "az.cmd" version;
        }
    };
    'gh' = @{
        'url' = 'https://github.com/cli/cli/releases/download/v{0}/gh_{0}_windows_amd64.zip' -f $env:GH_VERSION;
        'local' = "$baseDir\gh.zip";
        'expandTo' = "$baseDir\gh.tmp";
        'postExpand' = {
            & Move-Item -Path "$baseDir\gh.tmp\bin\gh.exe" -Destination "$baseDir\gh.exe";
            & Remove-Item -Force -Recurse "$baseDir\gh.tmp";
        };
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & gh.exe version;
        }
    };
    'updatecli' = @{
        'url' = 'https://github.com/updatecli/updatecli/releases/download/v{0}/updatecli_Windows_x86_64.zip' -f $env:UPDATECLI_VERSION;
        'local' = "$baseDir\updatecli.zip";
        'expandTo' = "$baseDir\updatecli.tmp";
        'postExpand' = {
            & Move-Item -Path "$baseDir\updatecli.tmp\updatecli.exe" -Destination "$baseDir\updatecli.exe";
            & Remove-Item -Force -Recurse "$baseDir\updatecli.tmp";
        };
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & gh.exe version;
        }
    };
    'netlify-deploy' = @{
        'url' = 'https://github.com/halkeye/netlify-golang-deploy/releases/download/v{0}/netlify-golang-deploy_{0}_Windows_x86_64.zip' -f $env:NETLIFYDEPLOY_VERSION;
        'local' = "$baseDir\netlify-golang-deploy.zip";
        'expandTo' = "$baseDir\netlify-golang-deploy.tmp";
        'postExpand' = {
            & Move-Item -Path "$baseDir\netlify-golang-deploy.tmp\netlify-golang-deploy.exe" -Destination "$baseDir\netlify-deploy.exe";
            & Remove-Item -Force -Recurse "$baseDir\netlify-golang-deploy.tmp";
        };
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & netlify-deploy.exe --help;
        }
    };
    'terraform' = @{
        'url' = 'https://releases.hashicorp.com/terraform/{0}/terraform_{0}_windows_amd64.zip' -f $env:TERRAFORM_VERSION;
        'local' = "$baseDir\terraform.zip";
        'expandTo' = "$baseDir"; # Only terraform.exe
        'cleanupLocal' = 'true';
        'sanityCheck'= {
            & terraform.exe -v;
        };
    };
    'kubectl' = @{
        'url' = 'https://dl.k8s.io/release/v{0}/bin/windows/amd64/kubectl.exe'  -f $env:KUBECTL_VERSION;
        'local' = "$baseDir\kubectl.exe"
        'sanityCheck'= {
            & kubectl.exe version --client;
        }
    };
    'chocolatey-and-packages' = @{
        'url' = 'https://github.com/chocolatey/choco/releases/download/{0}/chocolatey.{0}.nupkg' -f $env:CHOCOLATEY_VERSION;
        'local' = "$baseDir\chocolatey.zip";
        'expandTo' = "$baseDir\chocolatey.tmp";
        'postExpand' = {
            # Installation of Chocolatey
            & "$baseDir\chocolatey.tmp\tools\chocolateyInstall.ps1";
            & Remove-Item -Force -Recurse "$baseDir\chocolatey.tmp";
        };
        'cleanupLocal' = 'true';
        'path' = "$baseDir\ruby26\bin\;C:\HashiCorp\Vagrant\;C:\Program Files\Amazon\AWSCLIV2\;c:\python311\;C:\python311\Scripts\;";
        'postInstall' = {
            # Installation of make for Windows
            & "choco.exe" install make --yes --no-progress --limit-output --fail-on-error-output;
            & "choco.exe" install vagrant --yes --no-progress --limit-output --fail-on-error-output --version "${env:VAGRANT_VERSION}";
            # Append a ".1" as all ruby packages in chocolatey have this suffix. Not sure why (maybe a package build id)
            & "choco.exe" install ruby --yes --no-progress --limit-output --fail-on-error-output --version "${env:RUBY_VERSION}.1";
            & "choco.exe" install yq --yes --no-progress --limit-output --fail-on-error-output --version "${env:YQ_VERSION}";
            & "choco.exe" install packer --yes --no-progress --limit-output --fail-on-error-output --version "${env:PACKER_VERSION}";
            & "choco.exe" install chromium --yes --no-progress --limit-output --fail-on-error-output;
            & "choco.exe" install awscli --yes --no-progress --limit-output --fail-on-error-output --version "${env:AWSCLI_VERSION}";
            & "choco.exe" install datadog-agent --yes --no-progress --limit-output --fail-on-error-output;
            & "choco.exe" install vcredist2015 --yes --no-progress --limit-output --fail-on-error-output;
            & "choco.exe" install trivy --yes --no-progress --limit-output --fail-on-error-output --version "${env:TRIVY_VERSION}";
            # Installation of python3 for Launchable
            & "choco.exe" install python3 --yes --no-progress --limit-output --fail-on-error-output --version "${env:PYTHON3_VERSION}";
            # Installation of Launchable globally (no other python tool)
            & "c:\python311\python.exe" -m pip --no-cache-dir --upgrade install setuptools wheel pip;
            & "c:\python311\python.exe" -m pip --no-cache-dir install launchable=="${env:LAUNCHABLE_VERSION}";
        };
        'sanityCheck'= {
            & choco.exe;
            & "C:\Program Files\Amazon\AWSCLIV2\aws.exe" --version;
            & make.exe -version;
            & packer.exe --version;
            & "$baseDir\ruby26\bin\ruby.exe" -v;
            & "$baseDir\ruby26\bin\bundle" -v;
            & updatecli.exe version;
            & yq.exe --version;
            & "c:\python311\python.exe" --version;
            & "C:\python311\Scripts\launchable.exe" --version;
        }
    };
}

## Add tools folder to PATH so we can sanity check them as soon as they are installed
AddToPathEnv $baseDir

## Sets the default JDK
$defaultJavaHome = '{0}\jdk-{1}' -f $baseDir,$env:DEFAULT_JDK
$defaultJavaBinPath = '{0}\bin' -f $defaultJavaHome
AddToPathEnv $defaultJavaBinPath
# env JAVA_HOME
New-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name 'JAVA_HOME' -Value $defaultJavaHome | Out-Null
## Maven requires the JAVA_HOME environment variable to be set. We use this value here: it is ephemeral.
$env:JAVA_HOME = $defaultJavaHome

## Proceed to install tools
# TODO: foreach in parallel for downloads
foreach($k in $downloads.Keys) {
    $download = $downloads[$k]
    if($download.ContainsKey('check')) {
        $res = Invoke-Command $download['check']
        if(!$res) {
            Write-Host "Check did not pass, not setting up $k"
            continue;
        }
    }
    Write-Host "Downloading and setting up $k"

    DownloadFile $download['url'] $download['local']
    if($download.ContainsKey('preexpand')) {
        Invoke-Command $download['preexpand']
    }

    if($download.ContainsKey('expandTo')) {
        Expand-Archive -Path $download['local'] -DestinationPath $download['expandTo']
    }

    if($download.ContainsKey('postExpand')) {
        Invoke-Command $download['postExpand']
    }

    if($download.ContainsKey('cleanupLocal')) {
        Remove-Item -Force $download['local']
    }

    if($download.ContainsKey('env')) {
        foreach($name in $download['env'].Keys) {
            $value = $download['env'][$name]
            New-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name $name -Value $val | Out-Null
        }
    }

    if($download.ContainsKey('path')) {
        AddToPathEnv $download['path']
    }

    if($download.ContainsKey('postInstall')) {
        Invoke-Command $download['postInstall']
    }
}

# Special case for Powershell, we need to make sure powershell.exe and pwsh.exe are both available
# On Windows Server, Windows Powershell 5.1 is installed by default (powershell.exe)
# On nanoserver, Powershell Core 7 is installed by default (pwsh.ex)
# https://docs.microsoft.com/en-us/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.2#using-powershell-7-side-by-side-with-windows-powershell-51
Write-Output "== Ensure both Windows Powershell and Powershell Core are available"
if ((Get-Host | Select-Object Version).Version.Major -eq 5) {
    Write-Output "= Windows Powershell already present, installing Powershell Core..."
    Invoke-Command {& "choco.exe" install pwsh --yes --no-progress --limit-output --fail-on-error-output --version "${env:WINDOWS_PWSH_VERSION}";}
    AddToPathEnv "C:\Program Files\PowerShell\7\"
} else {
    Write-Output "= Powershell Core already present, installing Windows Powershell..."
    Invoke-Command {& "choco.exe" install powershell --yes --no-progress --limit-output --fail-on-error-output;}
    AddToPathEnv "C:\Windows\System32\WindowsPowerShell\v1.0\"
}
Write-Output "= Windows Powershell & Powershell Core sanity checks:"
Invoke-Command {& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -command "(Get-Host).Version"}
Invoke-Command {& "C:\Program Files\PowerShell\7\pwsh.exe" -command "(Get-Host).Version"}

## Add a set of pre-defined SSH keys to allow faster agent startups
$temp_authorized_keys_file = 'C:\custom_auth_keys'
DownloadFile "$env:OPENSSH_AUTHORIZED_KEYS_URL" "$temp_authorized_keys_file"
foreach($line in Get-Content "$temp_authorized_keys_file") {
    C:\addSSHPubKey.ps1 "$line"
}
Remove-Item -Force "$temp_authorized_keys_file"

## Final information: print out status
Write-Host "== OS Version"
[System.Environment]::OSVersion.Version

Write-Host "== Disks"
Get-WmiObject -Class Win32_logicaldisk -Filter "DriveType = '3'" |
Select-Object -Property DeviceID, DriveType, VolumeName,
@{L='FreeSpaceGB';E={"{0:N2}" -f ($_.FreeSpace /1GB)}},
@{L="Capacity";E={"{0:N2}" -f ($_.Size/1GB)}} | Format-Table -Property DeviceID, VolumeName, FreeSpaceGB, Capacity

Write-Host "== Patch(s) installed"
Get-HotFix | Format-Table -Property HotFixID, Description, InstalledOn

Write-Host "== Sanity Check of installed tools"
Write-Host "- Path environment"
Write-Host (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
Write-Host '- Sanity check for docker'
& docker -v ## Client only
foreach($k in $downloads.Keys) {
    $download = $downloads[$k]
    if($download.ContainsKey('sanityCheck')) {
        Write-Host "- Sanity check for $k"
        Invoke-Command $download['sanityCheck']
    }
}
Write-Host "== End of Sanity Check"
