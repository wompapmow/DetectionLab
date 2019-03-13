# Purpose: Sets timezone to UTC, sets hostname, creates/joins domain.
# Source: https://github.com/StefanScherer/adfs2

$hostname = $env:ComputerName.ToLower()

Write-Host "Setting timezone to UTC"
c:\windows\system32\tzutil.exe /s "UTC"

if ($hostname -imatch 'vagrant') {

  Write-Host 'Hostname is still the original one, skip provisioning for reboot'

  Write-Host 'Install bginfo'
  . c:\vagrant\scripts\install-bginfo.ps1

  Write-Host -fore red 'Hint: vagrant reload' $hostname '--provision'  # this will display incorrectly if the hostname is not provisioned correctly.

} elseif ((gwmi win32_computersystem).partofdomain -eq $false) {

  Write-Host -fore red "Current domain is set to 'workgroup'. Time to join the domain!"

  if (!(Test-Path 'c:\Program Files\sysinternals\bginfo.exe')) {
    Write-Host 'Install bginfo'
    . c:\vagrant\scripts\install-bginfo.ps1
  }

  if ($hostname -imatch 'dc') {
    . c:\vagrant\scripts\create-domain.ps1 192.168.38.102
  } else {
    . c:\vagrant\scripts\join-domain.ps1
  }
  Write-Host -fore red 'Hint: vagrant reload' $hostname '--provision'

} else {

  Write-Host -fore green "I am domain joined!"

  if (!(Test-Path 'c:\Program Files\sysinternals\bginfo.exe')) {
    Write-Host 'Install bginfo'
    . c:\vagrant\scripts\install-bginfo.ps1
  }

  Write-Host 'Provisioning after joining domain'

}
