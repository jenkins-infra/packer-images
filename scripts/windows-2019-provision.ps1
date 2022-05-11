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

Function AddToPath($path) {
    $oldPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
    $newPath = '{0};{1}' -f $path,$oldPath
    Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value $newPath | Out-Null
}

# Install OpenSSH (from Windows Features)
Write-Output "Setting up OpenSSH Server"
Write-Host "(host) setting up OpenSSH Server"

Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null

## Prepare Tools Installation
$baseDir = 'C:\tools'
New-Item -ItemType Directory -Path $baseDir -Force | Out-Null

## List of tools to use
$downloads = [ordered]@{
    'jdk11' = @{
        'url' = 'https://github.com/adoptium/temurin11-binaries/releases/download/jdk-{0}/OpenJDK11U-jdk_x64_windows_hotspot_{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JDK11_VERSION),$env:JDK11_VERSION.Replace('+', '_');
        'local' = "$baseDir\temurin11.zip";
        'expandTo' = $baseDir;
        'postexpand' = {
            & Move-Item -Path "$baseDir\jdk-11*" -Destination "$baseDir\jdk-11"
        };
        'cleanuplocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-11\bin\java.exe" -version;
        }
    };
    'jdk17' = @{
        'url' = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-{0}/OpenJDK17U-jdk_x64_windows_hotspot_{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JDK17_VERSION),$env:JDK17_VERSION.Replace('+', '_');
        'local' = "$baseDir\temurin17.zip";
        'expandTo' = $baseDir;
        'postexpand' = {
            & Move-Item -Path "$baseDir\jdk-17*" -Destination "$baseDir\jdk-17"
        };
        'cleanuplocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-17\bin\java.exe" -version;
        }
    };
    'jdk8' = @{
        'url' = 'https://github.com/adoptium/temurin8-binaries/releases/download/jdk{0}/OpenJDK8U-jdk_x64_windows_hotspot_{1}.zip' -f $env:JDK8_VERSION,$env:JDK8_VERSION.Replace('-', '');
        'local' = "$baseDir\temurin8.zip";
        'expandTo' = $baseDir;
        'postexpand' = {
            & Move-Item -Path "$baseDir\jdk8*" -Destination "$baseDir\jdk-8"
        };
        'cleanuplocal' = 'true';
        # folder included here since it's not in the PATH
        'sanityCheck'= {
            & "$baseDir\jdk-17\bin\java.exe" -version;
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
        'cleanuplocal' = 'true';
        'sanityCheck'= {
            & "mvn.exe" -version;
        }
    };
    'git' = @{
        'url' = 'https://github.com/git-for-windows/git/releases/download/v{0}.windows.1/MinGit-{0}-64-bit.zip' -f $env:GIT_WINDOWS_VERSION;
        'local' = "$baseDir\MinGit.zip";
        'expandTo' = "$baseDir\git";
        'postexpand' = {
            & "$baseDir\git\cmd\git.exe" config --system core.autocrlf false;
            & "$baseDir\git\cmd\git.exe" config --system core.longpaths true;
        };
        'path' = "$baseDir\git\cmd";
        'cleanuplocal' = 'true';
        'sanityCheck'= {
            & "git.exe" -version;
        }
    };
    'gitlfs' = @{
        'url' = 'https://github.com/git-lfs/git-lfs/releases/download/v{0}/git-lfs-windows-amd64-v{0}.zip' -f $env:GIT_LFS_VERSION;
        'local' = "$baseDir\GitLfs.zip";
        'expandTo' = "$baseDir\git\mingw64\bin";
        'postexpand' = {
            & "$baseDir\git\cmd\git.exe" lfs install;
        };
        'path' = "$baseDir\git\mingw64\bin";
        'cleanuplocal' = 'true';
        'sanityCheck'= {
            & "git-lfs.exe" -version;
        }
    };
    'dockercompose' = @{
        'url' = 'https://github.com/docker/compose/releases/download/v{0}/docker-compose-Windows-x86_64.exe' -f $env:COMPOSE_VERSION;
        'local' = "$baseDir\docker-compose.exe"
        'sanityCheck'= {
            & "docker-compose.exe" -version;
        }
    };
    'hadolint' = @{
        'url' = 'https://github.com/hadolint/hadolint/releases/download/v{0}/hadolint-Windows-x86_64.exe' -f $env:HADOLINT_VERSION;
        'local' = "$baseDir\hadolint.exe"
        'sanityCheck'= {
            & "hadolint.exe" -version;
        }
    };
    'cst' = @{
        'url' = 'https://github.com/GoogleContainerTools/container-structure-test/releases/download/v{0}/container-structure-test-windows-amd64.exe' -f $env:CST_VERSION;
        'local' = "$baseDir\container-structure-test.exe"
        'sanityCheck'= {
            & "container-structure-test.exe" -version;
        }
    };
    'jx-release-version' = @{
        'url' = 'https://github.com/jenkins-x-plugins/jx-release-version/releases/download/v{0}/jx-release-version-windows-amd64.zip' -f $env:JXRELEASEVERSION_VERSION;
        'local' = "$baseDir\jx-release-version.zip"
        'expandTo' = $baseDir;
        'cleanuplocal' = 'true';
        'sanityCheck'= {
            & "jx-release-version.exe" -version;
        }
    };
    'jq' = @{
        'url' = 'https://github.com/stedolan/jq/releases/download/jq-{0}/jq-win64.exe'  -f $env:JQ_VERSION;
        'local' = "$baseDir\jq.exe"
        'sanityCheck'= {
            & "jq.exe" -version;
        }
    };
    'az' = @{
        'url' = 'https://azcliprod.blob.core.windows.net/msi/azure-cli-{0}.msi' -f $env:AZURECLI_VERSION;
        'local' = "$baseDir\AzureCLI.msi";
        'postexpand' = {
            ## Add these options to msiexec.exe to write debug to the log file
            # /L*V "C:\package.log"
            Start-Process msiexec.exe -Wait -ArgumentList "/i $baseDir\AzureCLI.msi /quiet /L*V C:\package.log";
        };
        'cleanuplocal' = 'true';
        'path' = 'C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\';
        'sanityCheck'= {
            & "az.cmd" -version;
        }
    };
    'gh' = @{
        'url' = 'https://github.com/cli/cli/releases/download/v{0}/gh_{0}_windows_amd64.zip' -f $env:GH_VERSION;
        'local' = "$baseDir\gh.zip";
        'expandTo' = "$baseDir\gh.tmp";
        'postexpand' = {
            & Move-Item -Path "$baseDir\gh.tmp\bin\gh.exe" -Destination "$baseDir\gh.exe";
            & Remove-Item -Force -Recurse "$baseDir\gh.tmp";
        };
        'cleanuplocal' = 'true';
        'sanityCheck'= {
            & "gh.exe" -version;
        }
    };
    'chocolatey' = @{
        'url' = 'https://github.com/chocolatey/choco/releases/download/{0}/chocolatey.{0}.nupkg' -f $env:CHOCOLATEY_VERSION;
        'local' = "$baseDir\chocolatey.zip";
        'expandTo' = "$baseDir\chocolatey.tmp";
        'postexpand' = {
            & "$baseDir\chocolatey.tmp\tools\chocolateyInstall.ps1";
            & "C:\ProgramData\chocolatey\bin\choco.exe" install make; # -- version $env:MAKE_VERSION";
            & Remove-Item -Force -Recurse "$baseDir\chocolatey.tmp";
        };
        'cleanuplocal' = 'true'
        'sanityCheck'= {
            & "choco.exe";
            & "make.exe" -version;
        }
    };
}

## Add tools folder to PATH so we can sanity check them as soon as they are installed
AddToPath $baseDir

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

    if($download.ContainsKey('postexpand')) {
        Invoke-Command $download['postexpand']
    }

    if($download.ContainsKey('cleanuplocal')) {
        Remove-Item -Force $download['local']
    }

    if($download.ContainsKey('env')) {
        foreach($name in $download['env'].Keys) {
            $value = $download['env'][$name]
            New-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name $name -Value $val | Out-Null
        }
    }

    if($download.ContainsKey('path')) {
        AddToPath $download['path']
    }
}

## Sets the default JDK
$defaultJavaHome = '{0}\jdk-{1}' -f $baseDir,$env:DEFAULT_JDK
$defaultJavaBinPath = '{0}\bin' -f $defaultJavaHome
AddToPath $defaultJavaBinPath
# env JAVA_HOME
New-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name 'JAVA_HOME' -Value $defaultJavaHome | Out-Null

## Add a set of pre-defined SSH keys to allow faster agent startups
$temp_authorized_keys_file = 'C:\custom_auth_keys'
DownloadFile "$env:OPENSSH_AUTHORIZED_KEYS_URL" "$temp_authorized_keys_file"
foreach($line in Get-Content "$temp_authorized_keys_file") {
    C:\addSSHPubKey.ps1 "$line"
}
Remove-Item -Force "$temp_authorized_keys_file"

## Final information: print out status
Write-Host "OS Version"
[System.Environment]::OSVersion.Version

Write-Host "Disks"
Get-WmiObject -Class Win32_logicaldisk -Filter "DriveType = '3'" |
Select-Object -Property DeviceID, DriveType, VolumeName,
@{L='FreeSpaceGB';E={"{0:N2}" -f ($_.FreeSpace /1GB)}},
@{L="Capacity";E={"{0:N2}" -f ($_.Size/1GB)}} | Format-Table -Property DeviceID, VolumeName, FreeSpaceGB, Capacity

Write-Host "Patch(s) installed"
Get-HotFix | Format-Table -Property HotFixID, Description, InstalledOn

Write-Host "== Sanity Check of installed tools"
& docker -v ## Client only

foreach($k in $downloads.Keys) {
    $download = $downloads[$k]
    if($download.ContainsKey('sanityCheck')) {
        echo "Sanity check for $k"
        Invoke-Command $download['sanityCheck']
    }
}

## Maven requires the JAVA_HOME environment variable to be set. We use this value here: it is ephemeral.
$env:JAVA_HOME = $defaultJavaHome
$mavenBin = '{0}\apache-maven-{1}\bin\mvn.cmd' -f $baseDir,$env:MAVEN_VERSION
& "$mavenBin" -v
