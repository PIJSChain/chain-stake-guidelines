# ============================================================
# PIJS Consensus Node Upgrade Script (Windows PowerShell)
# For hard fork upgrades - updates client and chain config only
# Does NOT delete existing chain data
# ============================================================

$ErrorActionPreference = "Stop"

# ==================== Configuration ====================
$GITHUB_RELEASE = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6k"
$GETH_VERSION = "v1.25.6k"
$GENESIS_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json"

# Default directory
$DEFAULT_INSTALL_DIR = "$env:USERPROFILE\pijs-node"

# ==================== Utility Functions ====================

function Write-Banner {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "    PIJS Consensus Node Upgrade Script" -ForegroundColor Blue
    Write-Host "    Target Version: $GETH_VERSION" -ForegroundColor Blue
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

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

# Check if node is running
function Test-NodeRunning {
    param([string]$InstallDir)
    $processes = Get-Process -Name "geth" -ErrorAction SilentlyContinue
    foreach ($proc in $processes) {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
            if ($cmdLine -like "*$InstallDir*") {
                return $true
            }
        } catch {
            # Ignore errors
        }
    }
    return $false
}

# Stop running node
function Stop-Node {
    param([string]$InstallDir)

    Write-Step "1" "Checking node status"

    if (Test-NodeRunning -InstallDir $InstallDir) {
        Write-Warn "Node is currently running, stopping..."

        $processes = Get-Process -Name "geth" -ErrorAction SilentlyContinue
        foreach ($proc in $processes) {
            try {
                $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                if ($cmdLine -like "*$InstallDir*") {
                    Stop-Process -Id $proc.Id -Force
                }
            } catch {
                # Ignore errors
            }
        }

        Start-Sleep -Seconds 3

        if (Test-NodeRunning -InstallDir $InstallDir) {
            Write-Error "Failed to stop node, please stop it manually first"
            exit 1
        }
        Write-Success "Node stopped"
    } else {
        Write-Info "Node is not running"
    }
}

# Backup current client
function Backup-Client {
    param([string]$InstallDir)

    Write-Step "2" "Backing up current client"

    $backupDir = Join-Path $InstallDir "backup"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $gethPath = Join-Path $InstallDir "bin\geth.exe"
    if (Test-Path $gethPath) {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupName = "geth.backup.$timestamp.exe"
        Copy-Item $gethPath (Join-Path $backupDir $backupName)
        Write-Success "Current client backed up to: $backupDir\$backupName"
    } else {
        Write-Info "No existing client to backup"
    }
}

# Download new client
function Download-Client {
    param([string]$InstallDir)

    Write-Step "3" "Downloading new client ($GETH_VERSION)"

    $gethFilename = "geth-windows-amd64.exe"
    $downloadUrl = "$GITHUB_RELEASE/$gethFilename"

    Write-Info "Downloading from: $downloadUrl"

    $binDir = Join-Path $InstallDir "bin"
    $gethPath = Join-Path $binDir "geth.exe"
    $tempPath = Join-Path $binDir "geth.new.exe"

    # Ensure directory exists
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # Download to temp file
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force
    }

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing
    } catch {
        Write-Error "Download failed: $_"
        exit 1
    }

    # Verify download
    if (-not (Test-Path $tempPath) -or (Get-Item $tempPath).Length -eq 0) {
        Write-Error "Download failed or file is empty"
        exit 1
    }

    # Verify it's a valid PE executable (check MZ header)
    $bytes = [System.IO.File]::ReadAllBytes($tempPath)[0..1]
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        Write-Error "Downloaded file is not a valid Windows executable"
        Remove-Item $tempPath -Force
        exit 1
    }

    # Remove old file and move new file
    if (Test-Path $gethPath) {
        Remove-Item $gethPath -Force
    }
    Move-Item $tempPath $gethPath -Force

    # Show version
    try {
        $version = & $gethPath version 2>&1 | Select-String "Version:" | Select-Object -First 1
        Write-Success "New client downloaded: $version"
    } catch {
        Write-Success "New client downloaded"
    }
}

# Download genesis file
function Download-Genesis {
    param([string]$InstallDir)

    Write-Step "4" "Downloading genesis configuration"

    $genesisPath = Join-Path $InstallDir "genesis.json"

    # Backup old genesis
    if (Test-Path $genesisPath) {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        Rename-Item $genesisPath "genesis.json.backup.$timestamp"
    }

    Write-Info "Downloading from: $GENESIS_URL"

    try {
        Invoke-WebRequest -Uri $GENESIS_URL -OutFile $genesisPath -UseBasicParsing
    } catch {
        Write-Error "Failed to download genesis.json: $_"
        exit 1
    }

    if (-not (Test-Path $genesisPath) -or (Get-Item $genesisPath).Length -eq 0) {
        Write-Error "Failed to download genesis.json"
        exit 1
    }

    Write-Success "Genesis configuration downloaded"
}

# Re-initialize chain config (for hard fork)
function Initialize-Chain {
    param([string]$InstallDir)

    Write-Step "5" "Re-initializing chain config (hard fork)"

    Write-Warn "This will update chain config only, existing chain data will be preserved"
    Write-Host ""

    $gethPath = Join-Path $InstallDir "bin\geth.exe"
    $dataDir = Join-Path $InstallDir "data"
    $genesisPath = Join-Path $InstallDir "genesis.json"

    Write-Info "Running: geth init --datadir `"$dataDir`" `"$genesisPath`""

    & $gethPath init --datadir $dataDir $genesisPath
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Chain config updated successfully"
    } else {
        Write-Error "Failed to update chain config"
        exit 1
    }
}

# Show completion info
function Show-Completion {
    param([string]$InstallDir)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "        Upgrade Complete!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Upgrade Summary:" -ForegroundColor Blue
    Write-Host "  New version: $GETH_VERSION"
    Write-Host "  Install directory: $InstallDir"
    Write-Host "  Chain data: Preserved"
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Blue
    Write-Host "  1. Start node: $InstallDir\start-node.ps1"
    Write-Host "  2. Or background start: $InstallDir\start-node-bg.ps1"
    Write-Host "  3. Check logs: Get-Content $InstallDir\logs\geth.log -Tail 50 -Wait"
    Write-Host ""
    Write-Host "Important:" -ForegroundColor Yellow
    Write-Host "  - If upgrade fails, restore backup from: $InstallDir\backup\"
    Write-Host "  - Monitor logs after restart to ensure node syncs correctly"
    Write-Host ""
}

# ==================== Main Process ====================

function Main {
    Write-Banner

    # Get install directory
    $installDir = Read-Host "Enter node installation directory [$DEFAULT_INSTALL_DIR]"
    if ([string]::IsNullOrWhiteSpace($installDir)) {
        $installDir = $DEFAULT_INSTALL_DIR
    }

    # Verify directory exists
    if (-not (Test-Path $installDir)) {
        Write-Error "Directory does not exist: $installDir"
        exit 1
    }

    $dataDir = Join-Path $installDir "data"
    if (-not (Test-Path $dataDir)) {
        Write-Error "Data directory not found. Is this a valid PIJS node installation?"
        exit 1
    }

    Write-Info "Upgrading node at: $installDir"
    Write-Host ""

    # Confirm upgrade
    Write-Host "WARNING: This will upgrade your node to version $GETH_VERSION" -ForegroundColor Yellow
    Write-Host "Chain data will be preserved, only client and config will be updated."
    Write-Host ""
    $confirm = Read-Host "Continue with upgrade? (y/n)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Upgrade cancelled"
        exit 0
    }

    Stop-Node -InstallDir $installDir
    Backup-Client -InstallDir $installDir
    Download-Client -InstallDir $installDir
    Download-Genesis -InstallDir $installDir
    Initialize-Chain -InstallDir $installDir

    Show-Completion -InstallDir $installDir
}

# Run main process
Main
