# Purpose: Joins a Windows host to the windomain.local domain which was created with "create-domain.ps1".
# Source: https://github.com/StefanScherer/adfs2

Write-Host 'Join the domain'

Write-Host "First, set DNS to DC to join the domain"
$newDNSServers = "192.168.38.102"
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPAddress -match "192.168.38."}
$adapters | ForEach-Object {$_.SetDNSServerSearchOrder($newDNSServers)}

Write-Host "Now join the domain"
$hostname = $env:computername
$user = "windomain.local\vagrant"
$pass = ConvertTo-SecureString "vagrant" -AsPlainText -Force
$DomainCred = New-Object System.Management.Automation.PSCredential $user, $pass

# Place the computer in the correct OU based on hostname
If ($hostname -eq "wef") {
  Add-Computer -DomainName "windomain.local" -credential $DomainCred -OUPath "ou=Servers,dc=windomain,dc=local" -PassThru
} ElseIf ($hostname -like "win10*") {
  Write-Host "Adding $hostname to the domain. Sometimes this step times out. If that happens, just run 'vagrant reload $hostname --provision'" #debug
  Add-Computer -DomainName "windomain.local" -credential $DomainCred -OUPath "ou=Workstations,dc=windomain,dc=local"
} Else {
  Add-Computer -DomainName "windomain.local" -credential $DomainCred -PassThru
}

Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoAdminLogon -Value 1
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultUserName -Value "vagrant"
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultPassword -Value "vagrant"
