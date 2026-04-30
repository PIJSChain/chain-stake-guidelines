#Requires -Version 5.1

# ============================================================
# PIJS Binary Update Script (Windows PowerShell)
# Downloads the latest binary release and adds it to PATH
# Does not touch chain data or genesis config
# ============================================================

$ErrorActionPreference = "Stop"

# ==================== Configuration ====================
$GitHubRepo = "PIJSChain/pijs"
$LatestReleaseApi = "https://api.github.com/repos/$GitHubRepo/releases/latest"
$DefaultInstallDir = "$env:USERPROFILE\pijs-node"
$BinaryNames = @("geth.exe", "bootnode.exe", "abigen.exe", "clef.exe", "evm.exe", "rlpdump.exe", "devp2p.exe", "ethkey.exe", "p2psim.exe")

# ==================== Utility Functions ====================

function Write-Banner {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "    PIJS Binary Update Script" -ForegroundColor Blue
    Write-Host "    Automatically updates the latest geth / bootnode tools" -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host ""
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[Step $Step] $Message" -ForegroundColor Green
    Write-Host "------------------------------------------------------------"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

# Validate that a file is a complete gzip archive (guards against truncated downloads or HTML error pages)
function Test-GzipArchive {
    param([string]$Path, [long]$MinSize = 1048576)

    if (-not (Test-Path $Path)) {
        Write-Error-Custom "Downloaded file not found: $Path"
        return $false
    }

    $size = (Get-Item $Path).Length
    if ($size -lt $MinSize) {
        Write-Error-Custom "Downloaded file too small ($size bytes, expected >= $MinSize), likely truncated"
        return $false
    }

    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $magic = New-Object byte[] 2
        [void]$stream.Read($magic, 0, 2)
        $stream.Close()
    } catch {
        Write-Error-Custom "Cannot read downloaded file: $_"
        return $false
    }

    if ($magic[0] -ne 0x1f -or $magic[1] -ne 0x8b) {
        $hex = "{0:X2}{1:X2}" -f $magic[0], $magic[1]
        Write-Error-Custom "Not a valid gzip archive (magic=$hex), download may have been truncated or redirected to an HTML page"
        return $false
    }

    return $true
}

# ==================== Main Workflow ====================

function Test-Dependencies {
    Write-Step "1" "Checking runtime requirements"

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Error-Custom "PowerShell 5.1 or later is required"
        exit 1
    }

    if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
        Write-Error-Custom "tar was not found. Please use Windows 10/11 or install tar first"
        exit 1
    }

    Write-Success "Runtime requirements look good"
}

function Get-LatestVersion {
    Write-Step "2" "Checking the latest release"

    try {
        $release = Invoke-RestMethod -Uri $LatestReleaseApi
    } catch {
        Write-Error-Custom "Failed to query GitHub Release: $_"
        exit 1
    }

    if (-not $release.tag_name) {
        Write-Error-Custom "Failed to resolve the latest release tag"
        exit 1
    }

    $script:LatestVersion = $release.tag_name
    $script:ReleaseDownloadBase = "https://github.com/$GitHubRepo/releases/download/$($script:LatestVersion)"
    Write-Success "Latest version: $($script:LatestVersion)"
}

function Backup-Binaries {
    param([string]$InstallDir)

    Write-Step "3" "Backing up existing binaries"

    $binDir = Join-Path $InstallDir "bin"
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupDir = Join-Path $InstallDir "backup\binaries-$timestamp"
    $found = $false

    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    foreach ($binary in $BinaryNames) {
        $sourcePath = Join-Path $binDir $binary
        if (Test-Path $sourcePath) {
            if (-not $found) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                $found = $true
            }
            Copy-Item $sourcePath (Join-Path $backupDir $binary) -Force
        }
    }

    if ($found) {
        Write-Success "Backed up to: $backupDir"
    } else {
        Write-Info "No existing binaries were found to back up"
    }
}

function Install-LatestBinaries {
    param([string]$InstallDir)

    Write-Step "4" "Downloading and installing the latest binaries"

    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Error-Custom "Only Windows amd64 binary packages are currently supported"
        exit 1
    }

    $platform = "windows-amd64"
    $archiveName = "geth-$($script:LatestVersion)-$platform.tar.gz"
    $downloadUrl = "$($script:ReleaseDownloadBase)/$archiveName"
    $binDir = Join-Path $InstallDir "bin"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pijs-binaries-" + [System.Guid]::NewGuid().ToString("N"))
    $archivePath = Join-Path $tempRoot $archiveName

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null

    try {
        Write-Info "Download URL: $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing

        # Verify download integrity (size + gzip magic)
        if (-not (Test-GzipArchive -Path $archivePath)) {
            throw "Downloaded archive failed validation. Please check your network and retry, or download manually: $downloadUrl"
        }

        tar -xzf $archivePath -C $tempRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Extraction failed (tar exit code: $LASTEXITCODE), archive may be corrupted"
        }

        $installed = $false
        foreach ($binary in $BinaryNames) {
            $sourcePath = Join-Path $tempRoot $binary
            if (Test-Path $sourcePath) {
                Move-Item $sourcePath (Join-Path $binDir $binary) -Force
                $installed = $true
                Write-Info "Updated: $binary"
            }
        }

        if (-not $installed) {
            throw "No installable binaries were found in the archive"
        }
    } catch {
        Write-Error-Custom "Failed to install binaries: $_"
        exit 1
    } finally {
        if (Test-Path $tempRoot) {
            Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $gethPath = Join-Path $binDir "geth.exe"
    if (-not (Test-Path $gethPath)) {
        Write-Error-Custom "Extraction completed but geth.exe was not found; archive contents are abnormal"
        exit 1
    }

    $versionOutput = & $gethPath version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "geth.exe failed to run (exit code: $LASTEXITCODE):"
        Write-Host ($versionOutput -join "`n")
        exit 1
    }

    $matchedVersion = $versionOutput | Select-String "Version:" | Select-Object -First 1
    $versionLine = if ($matchedVersion) { $matchedVersion.ToString().Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($versionLine)) {
        Write-Success "Binary update complete, release tag: $($script:LatestVersion)"
    } elseif ($versionLine -match [regex]::Escape($script:LatestVersion) -or $versionLine -match [regex]::Escape($script:LatestVersion.TrimStart('v'))) {
        Write-Success "Binary update complete: $versionLine"
    } else {
        Write-Success "Binary update complete, release tag: $($script:LatestVersion), $versionLine"
    }
}

function Update-PathVariable {
    param([string]$InstallDir)

    Write-Step "5" "Updating PATH"

    $binDir = Join-Path $InstallDir "bin"
    $env:PATH = "$binDir;$env:PATH"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $pathEntries = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $exists = $false
    foreach ($entry in $pathEntries) {
        if ($entry.TrimEnd('\\') -ieq $binDir.TrimEnd('\\')) {
            $exists = $true
            break
        }
    }

    if ($exists) {
        Write-Info "User PATH already contains: $binDir"
    } else {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $binDir } else { "$binDir;$userPath" }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Success "Added to user PATH: $binDir"
    }
}

function Show-Completion {
    param([string]$InstallDir)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "        Binary Update Complete!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Blue
    Write-Host "  Latest version: $($script:LatestVersion)"
    Write-Host "  Install directory: $InstallDir"
    Write-Host "  Binary directory: $(Join-Path $InstallDir 'bin')"
    Write-Host "  Chain data: unchanged"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Blue
    Write-Host "  1. Re-open PowerShell so PATH changes take effect"
    Write-Host "  2. Verify the version: geth version"
    Write-Host "  3. If this release includes a hard fork, use upgrade-node.ps1 instead"
    Write-Host ""
}

function Main {
    Write-Banner
    Write-Warn "This script only updates binaries and PATH. It does not update genesis.json or re-run init."
    Write-Host ""

    $installDir = Read-Host "Enter the binary install directory [$DefaultInstallDir]"
    if ([string]::IsNullOrWhiteSpace($installDir)) {
        $installDir = $DefaultInstallDir
    }

    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    Write-Info "Target directory: $installDir"

    Test-Dependencies
    Get-LatestVersion
    Backup-Binaries -InstallDir $installDir
    Install-LatestBinaries -InstallDir $installDir
    Update-PathVariable -InstallDir $installDir
    Show-Completion -InstallDir $installDir
}

Main
