# This script ensures that the public keys passed as argument $args[0]
# is set up as an SSH authorized key for the user passed as argument $args[1]

## Fail fast - equivalent of "set -e"
$ErrorActionPreference = 'Stop'

## Uncomment to enable Verbose mode - equivalent of "set -x"
# https://stackoverflow.com/questions/41324882/how-to-run-a-powershell-script-with-verbose-output
# $VerbosePreference="Continue"
# Set-PSDebug -Trace 1

## Enable unprivileged actions for this script
# See https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force

## Define Settings
$publicKey = $args[0]
$authorizedKeysFile = 'C:\ProgramData\ssh\administrators_authorized_keys'

Write-Output "Adding a new public key to $authorizedKeysFile..."
Write-Host "Adding a new public key to $authorizedKeysFile..."

## Add the key to the OpenSSH auth. keys SSH file
echo $publicKey | Out-File -Encoding ASCII -Append $authorizedKeysFile

## Define the correct file ACLs for the OpenSSH auth. keys SSH file
Write-Output "Setting ACLs on the file $authorizedKeysFile..."
Write-Host "Setting ACLs on the file $authorizedKeysFile..."
# Remove ACL inheritance
icacls $authorizedKeysFile /inheritance:r
# Allow access by SYSTEM profile
icacls $authorizedKeysFile /grant SYSTEM:`(F`)
# Allow acces by users of the Administrators group
icacls $authorizedKeysFile /grant Administrators:`(F`)

## If a user is provided, then update OpenSSH configuration to specify the key file for this user
if ($args[1]) {
  $partialSSHConfig = @"
Match User $args[1]
    AuthorizedKeysFile $authorizedKeysFile
"@
  echo "$partialSSHConfig" | Out-File -Encoding ASCII -Append 'C:\ProgramData\ssh\sshd_config'
}

## Ensure OpenSSH is reloaded
Restart-Service sshd

Write-Output "Key $publicKey added!"
Write-Host "Key $publicKey added!"
