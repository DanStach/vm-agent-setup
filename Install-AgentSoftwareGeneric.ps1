[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PAT,

    [Parameter(Mandatory = $true)]
    [string]$PoolName,

    [string]$VstsUrl = "https://<vsts-project-name>.visualstudio.com",
    [int]$AgentCount = 4,
    [bool]$InstallPrereqs = $true
)

Function Write-Status ($str)
{
    Write-Host "$(Get-Date -Format u) - $str"
}

$ErrorActionPreference = "Stop"

if ($InstallPrereqs) {
    Write-Status "Installing prereq. software"

    $ErrorActionPreference = "SilentlyContinue"
    $chocoVer = & choco -v
    $ErrorActionPreference = "Stop"

    if (-not $chocoVer) {
        Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }

    choco install dotnet4.5.2 -y

    Write-Status "NetFx3~~~"
    if ((Get-WindowsCapability -Name NetFx3~~~~ -Online).State -ine "Installed") {
        Add-WindowsCapability –Online -Name NetFx3~~~~
    }

    # See: https://github.com/Microsoft/dotnet-framework-docker/blob/master/3.5-windowsservercore-ltsc2016/sdk/Dockerfile

    # Install VS Test Agent
    $testAgentInstallPath = "$HOME\vs_TestAgent.exe"

    Write-Status "Installing VS Test Agent"
    Invoke-WebRequest -UseBasicParsing https://download.visualstudio.microsoft.com/download/pr/12210068/8a386d27295953ee79281fd1f1832e2d/vs_TestAgent.exe -OutFile $testAgentInstallPath
    Start-Process $testAgentInstallPath -ArgumentList '--quiet', '--norestart', '--nocache' -NoNewWindow -Wait

    # Install VS Build Tools
    $buildToolsPath = "$HOME\vs_BuildTools.exe"
    Write-Status "Done"

    Write-Status "Installing VS Build Tools"
    Invoke-WebRequest -UseBasicParsing https://download.visualstudio.microsoft.com/download/pr/12210059/e64d79b40219aea618ce2fe10ebd5f0d/vs_BuildTools.exe -OutFile $buildToolsPath
    # Installer won't detect DOTNET_SKIP_FIRST_TIME_EXPERIENCE if ENV is used, must use setx /M
    setx /M DOTNET_SKIP_FIRST_TIME_EXPERIENCE 1
    Start-Process $buildToolsPath -ArgumentList `
        '--add', 'Microsoft.VisualStudio.Workload.MSBuildTools', `
        '--add', 'Microsoft.VisualStudio.Workload.NetCoreBuildTools', `
        '--add', 'Microsoft.VisualStudio.Workload.AzureBuildTools', `
        '--add', 'Microsoft.VisualStudio.Workload.WebBuildTools', `
        '--add', 'Microsoft.VisualStudio.Workload.NodeBuildTools', `
        '--quiet', '--norestart', '--nocache', '--includeRecommended', '--includeOptional' -NoNewWindow -Wait
    Write-Status "Done"

    choco install nodejs -y
    choco install git.install -y
    choco install googlechrome -y

    Write-Status "Install AzurePS"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$False
    Install-Module -Name Azure -Force -Confirm:$False
    Install-Module -Name AzureRM -Force -Confirm:$False
}


if ($AgentCount -gt 0) {
    if (-not (Test-Path "$HOME\agent.zip")) {
        (New-Object System.Net.WebClient).DownloadFile("https://vstsagentpackage.azureedge.net/agent/2.140.0/vsts-agent-win-x64-2.140.0.zip", "$HOME\agent.zip")
    }

    foreach ($i in 0..($AgentCount - 1)) {

        $agentDir = "C:\agent$i"

        Write-Status "Agent #$i"
        try {
            New-Item $agentDir -ItemType Directory -ErrorAction Stop
        }
        catch {
            Write-Status "Skiping agent install, dir already exists C:\agent$i"
            Write-Host ""
            continue
        }

        cd $agentDir
        Write-Status "Unzipping agent to $(Convert-Path .)"
        Add-Type -AssemblyName System.IO.Compression.FileSystem ; [System.IO.Compression.ZipFile]::ExtractToDirectory("$HOME\agent.zip", "$PWD")

        Write-Status "Starting agent install"
        Write-Status ".\config.cmd --unattended --url $VstsUrl --auth pat --token--pool $PoolName --agent $env:COMPUTERNAME-$i --acceptTeeEula --runAsService"
        & .\config.cmd --unattended --url "$VstsUrl" --auth pat --token "$PAT" --pool "$PoolName" --agent "$env:COMPUTERNAME-$i" --acceptTeeEula --runAsService

        Write-Host ""
    }
}

Write-Status "Done-and-Done"