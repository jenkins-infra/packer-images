Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = 'Stop'

New-Item -Path "c:\" -Name "temp" -ItemType "directory"

Write-Host "Creating Dockerfile.ltsc2019"

$content = "FROM mcr.microsoft.com/windows/servercore:ltsc2019
RUN dism.exe /online /enable-feature /all /featurename:iis-webserver /NoRestart
RUN echo 'Hello World - Dockerfile' > c:\inetpub\wwwroot\index.html
"

Write-Host $content
Set-Content -Path "C:\temp\Dockerfile.ltsc2019" -Value $content -Force
Write-Host "Building Dockerfile.ltsc2019"
docker build -f C:\temp\Dockerfile.ltsc2019 C:\temp\

Write-Host "Creating Dockerfile.1809"

$content = "FROM mcr.microsoft.com/windows/servercore:1809
RUN dism.exe /online /enable-feature /all /featurename:iis-webserver /NoRestart
RUN echo 'Hello World - Dockerfile' > c:\inetpub\wwwroot\index.html
"

Write-Host $content
Set-Content -Path "C:\temp\Dockerfile.1809" -Value $content -Force
Write-Host "Building Dockerfile.1809"
docker build -f C:\temp\Dockerfile.1809 C:\temp\
