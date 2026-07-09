# install-prerequisites-windows.ps1
# Windows version of install-prerequisites-mac.sh
# Installs: Terraform, kubectl, Helm, eksctl, AWS CLI v2, and MuleSoft rtfctl.
#
# Recommended:
#   Run PowerShell as Administrator for machine-wide PATH updates.
#
# Run:
#   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
#   Unblock-File .\install-prerequisites-windows.ps1
#   .\install-prerequisites-windows.ps1

$ErrorActionPreference = "Stop"

function Log {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-CommandExists {
    param([string]$CommandName)
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Add-ToPath {
    param(
        [string]$Directory,
        [ValidateSet("User", "Machine")]
        [string]$Scope
    )

    $currentPath = [Environment]::GetEnvironmentVariable("Path", $Scope)

    if ($currentPath -notlike "*$Directory*") {
        Log "Adding $Directory to $Scope PATH..."
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$Directory", $Scope)
        Refresh-Path
    } else {
        Log "$Directory already exists in $Scope PATH."
    }
}

function Install-WithWinget {
    param(
        [string]$Name,
        [string]$CommandName,
        [string]$PackageId
    )

    if (Test-CommandExists $CommandName) {
        Log "$Name already installed."
        return
    }

    if (!(Test-CommandExists "winget")) {
        throw "winget is not available. Install 'App Installer' from Microsoft Store, then rerun this script."
    }

    Log "Installing $Name using winget package: $PackageId"

    winget install `
        --exact `
        --id $PackageId `
        --source winget `
        --accept-source-agreements `
        --accept-package-agreements `
        --silent

    Refresh-Path

    if (Test-CommandExists $CommandName) {
        Log "$Name installed successfully."
    } else {
        Warn "$Name installation completed, but command '$CommandName' is not available in this PowerShell session yet."
        Warn "Close and reopen PowerShell, then verify using: $CommandName --version"
    }
}

Log "Starting prerequisite installation for Windows..."

$isAdmin = Test-IsAdmin

if ($isAdmin) {
    Log "PowerShell is running as Administrator."
} else {
    Warn "PowerShell is not running as Administrator."
    Warn "winget may still work, but PATH changes for rtfctl will be applied only to the current user."
}

Refresh-Path

# Install standard tools using winget.
Install-WithWinget -Name "Terraform" -CommandName "terraform" -PackageId "Hashicorp.Terraform"
Install-WithWinget -Name "kubectl"   -CommandName "kubectl"   -PackageId "Kubernetes.kubectl"
Install-WithWinget -Name "Helm"      -CommandName "helm"      -PackageId "Helm.Helm"
Install-WithWinget -Name "eksctl"    -CommandName "eksctl"    -PackageId "eksctl.eksctl"
Install-WithWinget -Name "AWS CLI v2" -CommandName "aws"      -PackageId "Amazon.AWSCLI"

# Install MuleSoft rtfctl for Windows.
if (Test-CommandExists "rtfctl") {
    Log "rtfctl already installed."
} else {
    Log "Installing MuleSoft rtfctl for Windows..."

    if ($isAdmin) {
        $rtfctlDir = "C:\Program Files\rtfctl"
        $pathScope = "Machine"
    } else {
        $rtfctlDir = Join-Path $env:USERPROFILE "tools\rtfctl"
        $pathScope = "User"
    }

    if (!(Test-Path $rtfctlDir)) {
        New-Item -ItemType Directory -Path $rtfctlDir -Force | Out-Null
    }

    $rtfctlExe = Join-Path $rtfctlDir "rtfctl.exe"
    $rtfctlUrl = "https://anypoint.mulesoft.com/runtimefabric/api/download/rtfctl-windows/latest"

    Log "Downloading rtfctl from MuleSoft..."
    Invoke-WebRequest -Uri $rtfctlUrl -OutFile $rtfctlExe

    Add-ToPath -Directory $rtfctlDir -Scope $pathScope

    if (Test-CommandExists "rtfctl") {
        Log "rtfctl installed successfully."
    } else {
        Warn "rtfctl was downloaded to: $rtfctlExe"
        Warn "Close and reopen PowerShell, then run: rtfctl -h"
    }
}

Log "Versions:"
try { aws --version } catch { Warn "AWS CLI version check failed." }
try { terraform version } catch { Warn "Terraform version check failed." }
try { kubectl version --client } catch { Warn "kubectl version check failed." }
try { helm version } catch { Warn "Helm version check failed." }
try { eksctl version } catch { Warn "eksctl version check failed." }
try {
    rtfctl -h | Out-Null
    Write-Host "rtfctl installed"
} catch {
    Warn "rtfctl version/help check failed."
}

Log "Prerequisite installation completed."
Log "If any command is not recognized, close and reopen PowerShell, then run the version checks again."
