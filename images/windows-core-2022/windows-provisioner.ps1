$ErrorActionPreference = "Continue"
$VerbosePreference = "Continue"

# Install Chocolatey
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$env:chocolateyUseWindowsCompression = 'true'
Invoke-WebRequest https://chocolatey.org/install.ps1 -UseBasicParsing | Invoke-Expression

# Add Chocolatey to powershell profile
$ChocoProfileValue = @'
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

refreshenv
'@
# Write it to the $profile location
Set-Content -Path "$PsHome\Microsoft.PowerShell_profile.ps1" -Value $ChocoProfileValue -Force
# Source it
. "$PsHome\Microsoft.PowerShell_profile.ps1"

refreshenv

Write-Host "Installing cloudwatch agent..."
Invoke-WebRequest -Uri https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi -OutFile C:\amazon-cloudwatch-agent.msi
$cloudwatchParams = '/i', 'C:\amazon-cloudwatch-agent.msi', '/qn', '/L*v', 'C:\CloudwatchInstall.log'
Start-Process "msiexec.exe" $cloudwatchParams -Wait -NoNewWindow
Remove-Item C:\amazon-cloudwatch-agent.msi

# Install dependent tools
Write-Host "Installing additional development tools"
# see https://github.com/actions/runner-images/blob/main/images/win/Windows2022-Readme.md
choco install git.install -y --params "'/GitAndUnixToolsOnPath /WindowsTerminal /NoAutoCrlf'"
choco install awscli yarn make 7zip aria2 jq -y
choco install golang --version=1.21.3 -y
choco install nodejs --version=20.8.1 -y
choco install mingw --version 12.2.0.03042023 --allow-downgrade -y
choco install windows-sdk-11-version-22h2-all -y
choco install powershell-core dotnet-desktopruntime -y
refreshenv

# Update PATH, required because windows-sdk does not correctly add makeappx.exe to path
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64", "Machine")

Write-Host "Creating actions-runner directory for the GH Action installtion"
New-Item -ItemType Directory -Path C:\actions-runner ; Set-Location C:\actions-runner

Write-Host "Downloading the GH Action runner from ${action_runner_url}"
Invoke-WebRequest -Uri ${action_runner_url} -OutFile actions-runner.zip

Write-Host "Un-zip action runner"
Expand-Archive -Path actions-runner.zip -DestinationPath .

Write-Host "Delete zip file"
Remove-Item actions-runner.zip

$action = New-ScheduledTaskAction -WorkingDirectory "C:\actions-runner" -Execute "PowerShell.exe" -Argument "-File C:\start-runner.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "runnerinit" -Action $action -Trigger $trigger -User System -RunLevel Highest -Force

& 'C:/Program Files/Amazon/EC2Launch/ec2launch' reset --block
& 'C:/Program Files/Amazon/EC2Launch/ec2launch' sysprep --block
