Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Web

$baseDir = 'c:\tools'
New-Item -ItemType Directory -Path $baseDir -Force | Out-Null

$downloads = [ordered]@{
    'jdk11' = @{
        'url' = 'https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-{0}/OpenJDK11U-jdk_x64_windows_hotspot_{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JDK11_VERSION),$env:JDK11_VERSION.Replace('+', '_');
        'local' = "$baseDir\adoptOpenJDK11.zip";
        'destination' = $baseDir;
        'env' = @{
            'JAVA_HOME' = '{0}\jdk-{1}' -f $baseDir,$env:JDK11_VERSION;
        };
        'path' = '{0}\jdk-{1}\bin' -f $baseDir,$env:JDK11_VERSION;
    };
    'jdk8' = @{
        'url' = 'https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk{0}/OpenJDK8U-jdk_x64_windows_hotspot_{1}.zip' -f $env:JDK8_VERSION,$env:JDK8_VERSION.Replace('-', '')
        'local' = "$baseDir\adoptOpenJDK8.zip";
        'destination' = $baseDir;
    };
    'maven' = @{
        'url' = 'https://apache.osuosl.org/maven/maven-3/{0}/binaries/apache-maven-{0}-bin.zip' -f $env:MAVEN_VERSION;
        'local' = "$baseDir\maven.zip";
        'destination' = $baseDir;
        'path' = '{0}\apache-maven-{1}\bin' -f $baseDir,$env:MAVEN_VERSION;
        'env' = @{
            'MAVEN_HOME' = '{0}\apache-maven-{1}' -f $baseDir,$env:MAVEN_VERSION;
        };
    };
    'git' = @{
        'url' = 'https://github.com/git-for-windows/git/releases/download/v{0}.windows.1/MinGit-{0}-64-bit.zip' -f $env:GIT_VERSION;
        'local' = "$baseDir\MinGit.zip";
        'destination' = "$baseDir\git";
        'postexpand' = {
            & "$baseDir\git\cmd\git.exe" config --system core.autocrlf false
            & "$baseDir\git\cmd\git.exe" config --system core.longpaths true
        };
        'path' = "$baseDir\git\cmd";
    };
    'gitlfs' = @{
        'url' = 'https://github.com/git-lfs/git-lfs/releases/download/v{0}/git-lfs-windows-amd64-v{0}.zip' -f $env:GIT_LFS_VERSION;
        'local' = "$baseDir\GitLfs.zip";
        'destination' = "$baseDir\git\mingw64\bin";
        'postexpand' = {
            & "$baseDir\git\cmd\git.exe" lfs install
        };
    };
    'openssh' = @{
        'check' = { -not [System.String]::IsNullOrWhiteSpace($env:OPENSSH_VERSION) };
        'url' = 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/{0}/OpenSSH-Win64.zip' -f $env:OPENSSH_VERSION;
        'local' = "$baseDir\openssh.zip";
        'destination' = 'C:\Program Files';
        'postexpand' = {
            New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
            powershell.exe -ExecutionPolicy Bypass -File 'C:\Program Files\OpenSSH-Win64\install-sshd.ps1'
            if(-not (Test-Path -Path $env:ProgramData/ssh)) {
                New-Item -ItemType Directory -Path $env:ProgramData/ssh
            }
            if(-not [System.String]::IsNullOrWhiteSpace($env:OPENSSH_PUBLIC_KEY)) {
                Set-Content -Path $env:ProgramData/ssh/administrators_authorized_keys -Value "$($env:OPENSSH_PUBLIC_KEY)" -Force
                icacls $env:ProgramData/ssh/administrators_authorized_keys /inheritance:r
                icacls $env:ProgramData/ssh/administrators_authorized_keys /grant SYSTEM:`(F`)
                icacls $env:ProgramData/ssh/administrators_authorized_keys /grant BUILTIN\Administrators:`(F`)
            }
            Set-Service sshd -StartupType Automatic | Out-Null
        }
    };
}

function DownloadFile($url, $targetFile) {
   $uri = New-Object "System.Uri" "$url"
   $request = [System.Net.HttpWebRequest]::Create($uri)
   $request.set_Timeout(15000) #15 second timeout
   $response = $request.GetResponse()
   $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
   $responseStream = $response.GetResponseStream()
   $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
   $buffer = new-object byte[] 10KB
   $count = $responseStream.Read($buffer,0,$buffer.length)
   $downloadedBytes = $count
   while ($count -gt 0) {
       $targetStream.Write($buffer, 0, $count)
       $count = $responseStream.Read($buffer,0,$buffer.length)
       $downloadedBytes = $downloadedBytes + $count
       Write-Progress -activity "Downloading file '$($url.split('/') | Select-Object -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)
   }
   Write-Progress -activity "Finished downloading file '$($url.split('/') | Select-Object -Last 1)'"
   $targetStream.Flush()
   $targetStream.Close()
   $targetStream.Dispose()
   $responseStream.Dispose()
}

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

    Expand-Archive -Path $download['local'] -DestinationPath $download['destination']

    if($download.ContainsKey('postexpand')) {
        Invoke-Command $download['postexpand']
    }

    Remove-Item -Force $download['local']

    if($download.ContainsKey('env')) {
        foreach($name in $download['env'].Keys) {
            $value = $download['env'][$name]
            New-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name $name -Value $val | Out-Null
        }
    }

    if($download.ContainsKey('path')) {
        $path = $download['path']
        $oldPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
        $newPath = "$oldPath;$path"
        Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value $newPath | Out-Null
    }
}

if(Test-Path 'C:\Program Files\Amazon\Ec2ConfigService\Settings\config.xml') {
    Write-Host 'Updating AWS configuration for passwords'
    # Enable the system password to be retrieved from the AWS Console after this AMI is built and used to launch code
    $ec2config = [xml] (Get-Content 'C:\Program Files\Amazon\Ec2ConfigService\Settings\config.xml')
    ($ec2config.ec2configurationsettings.plugins.plugin | Where-Object {$_.name -eq 'Ec2SetPassword'}).state = 'Enabled'
    $ec2config.Save('C:\Program Files\Amazon\Ec2ConfigService\Settings\config.xml')
}

if($env:CLOUD_TYPE -eq 'azure') {
    # Azure needs the image sysprep'd manually, AWS is done using AWS scripts from the json
    & $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit
    while($true) {
        $imageState = Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' | Select-Object ImageState
        if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
            Write-Output $imageState.ImageState
            Start-Sleep -s 5
        } else {
            break
        }
    }
}

[System.Environment]::OSVersion.Version
