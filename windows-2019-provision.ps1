Set-ExecutionPolicy Unrestricted
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseDir = 'c:\azurecsdir'

$JDKUrl = 'https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-{0}/OpenJDK11U-jdk_x64_windows_hotspot_{1}.zip' -f [System.Web.HTTPUtility]::UrlEncode($env:JAVA_VERSION),$env:JAVA_VERSION.Replace('+', '_')
$destinationJDKZipPath = "$baseDir\adoptOpenJDK.zip"
$javaHome = '{0}\jdk-{1}' -f $baseDir,$env:JAVA_VERSION

$GITUrl = 'https://github.com/git-for-windows/git/releases/download/v{0}.windows.1/MinGit-{0}-64-bit.zip' -f $env:GIT_VERSION
$destinationGitZipPath = "$baseDir\MinGit.zip"
$GITPath = "$baseDir\git\cmd\"

$MavenUrl = 'https://apache.osuosl.org/maven/maven-3/{0}/binaries/apache-maven-{0}-bin.zip' -f $env:MAVEN_VERSION
$destinationMavenZipPath = "$baseDir\maven.zip"
$mavenPath = '{0}\apache-maven-{1}\bin' -f $baseDir,$env:MAVEN_VERSION

function DownloadFile($url, $targetFile)
{
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

# Checking if this is first time script is getting executed, if yes then downloading JDK, Git and VS Tools
If(-not((Test-Path $destinationJDKZipPath)))
{
    New-Item -ItemType Directory -Path $baseDir -Force
    DownloadFile $JDKUrl $destinationJDKZipPath
    Expand-Archive -Path $destinationJDKZipPath -DestinationPath $baseDir
    Remove-Item -Force $destinationJDKZipPath

    DownloadFile $GITUrl $destinationGitZipPath
    New-Item -ItemType Directory -Path "$baseDir\git" -Force
    Expand-Archive -Path $destinationGitZipPath -DestinationPath $baseDir\git
    & "$GITPath\git" config --system core.autocrlf false
    & "$GITPath\git" config --system core.longpaths true
    Remove-Item -Force $destinationGitZipPath

    DownloadFile $MavenUrl $destinationMavenZipPath
    Expand-Archive -Path $destinationMavenZipPath -DestinationPath $baseDir
    Remove-Item -Force $destinationMavenZipPath

    # update the system path to include Git, Java and Maven
    $oldPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
    $newPath = "$oldPath;$javaHome\bin;$GITPath;$MavenPath"
    Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value $newPath
    # setup JAVA_HOME environment variable
    New-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name JAVA_HOME -Value $javaHome
}

#C:\Jenkins

& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit
while($true) {
    $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select-Object ImageState
    if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
        Write-Output $imageState.ImageState
        Start-Sleep -s 10
    } else {
        break
    }
}
