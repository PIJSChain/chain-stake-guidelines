# ============================================================
# PIJS Consensus Node Upgrade Script (Windows PowerShell)
# For hard fork upgrades - updates client and chain config only
# Does NOT delete existing chain data
# ============================================================

$ErrorActionPreference = "Stop"

# ==================== Configuration ====================
$GITHUB_RELEASE = "https://github.com/PIJSChain/pijs/releases/download/v1.26.0"
$GETH_VERSION = "v1.26.0"
$GENESIS_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.26.0/genesis.json"

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

    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    $platform = "windows-$arch"
    $gethTar = "geth-$GETH_VERSION-$platform.tar.gz"
    $downloadUrl = "$GITHUB_RELEASE/$gethTar"

    Write-Info "Downloading from: $downloadUrl"

    $downloadPath = Join-Path $InstallDir $gethTar

    # Download archive
    if (Test-Path $downloadPath) {
        Remove-Item $downloadPath -Force
    }

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
    } catch {
        Write-Error "Download failed: $_"
        exit 1
    }

    # Verify download
    if (-not (Test-Path $downloadPath) -or (Get-Item $downloadPath).Length -eq 0) {
        Write-Error "Download failed or file is empty"
        exit 1
    }

    # Extract
    Write-Info "Extracting files..."
    Set-Location $InstallDir
    tar -xzf $gethTar

    # Create bin directory
    $binDir = Join-Path $InstallDir "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # Move all binaries to bin directory
    $binaries = @("geth.exe", "bootnode.exe", "abigen.exe", "clef.exe", "evm.exe", "rlpdump.exe", "devp2p.exe", "ethkey.exe", "p2psim.exe")
    foreach ($binary in $binaries) {
        $srcPath = Join-Path $InstallDir $binary
        if (Test-Path $srcPath) {
            $destPath = Join-Path $binDir $binary
            if (Test-Path $destPath) {
                Remove-Item $destPath -Force
            }
            Move-Item $srcPath $destPath -Force
        }
    }

    # Clean up archive
    Remove-Item $downloadPath -Force

    # Show version
    $gethPath = Join-Path $binDir "geth.exe"
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

# Interactive NAT mode selection (consistent with setup)
function Choose-NatMode {
    Write-Host ""
    Write-Host "Please select your network environment:"
    Write-Host ""
    Write-Host "  1) Static public IP - Server has a static public IP address"
    Write-Host "  2) NAT environment  - Behind a router/NAT gateway (home networks, some cloud VMs)"
    Write-Host "  3) Auto-detect      - Detect public IP on every startup (recommended)"
    Write-Host ""

    $done = $false
    while (-not $done) {
        $choice = Read-Host "Please choose [1-3] (default: 3)"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "3" }

        switch ($choice) {
            "1" {
                Write-Host ""
                Write-Info "Detecting your public IP..."
                $detectedIp = $null
                foreach ($svc in @("https://ip.sb", "https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com", "https://ipinfo.io/ip")) {
                    try {
                        $result = (Invoke-WebRequest -Uri $svc -UseBasicParsing -TimeoutSec 5 -UserAgent "curl").Content.Trim()
                        if ($result -match "^\d+\.\d+\.\d+\.\d+$") {
                            $detectedIp = $result
                            break
                        }
                    } catch {
                        continue
                    }
                }

                if ($detectedIp) {
                    Write-Host "Detected IP: $detectedIp"
                    $confirm = Read-Host "Use this IP? (y/n, or enter a different IP)"
                    if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -match "^[Yy]$") {
                        $script:NAT_MODE = "extip"
                        $script:PUBLIC_IP = $detectedIp
                        $done = $true
                    } elseif ($confirm -match "^\d+\.\d+\.\d+\.\d+$") {
                        $script:NAT_MODE = "extip"
                        $script:PUBLIC_IP = $confirm
                        $done = $true
                    } else {
                        Write-Host "Invalid input, please try again"
                    }
                } else {
                    $manualIp = Read-Host "Failed to detect public IP, please enter your public IP manually"
                    if ($manualIp -match "^\d+\.\d+\.\d+\.\d+$") {
                        $script:NAT_MODE = "extip"
                        $script:PUBLIC_IP = $manualIp
                        $done = $true
                    } else {
                        Write-Error "Invalid IP address format"
                    }
                }
            }
            "2" {
                $script:NAT_MODE = "any"
                $script:PUBLIC_IP = ""
                Write-Info "NAT mode selected, will use UPnP/NAT-PMP for automatic port mapping"
                $done = $true
            }
            "3" {
                $script:NAT_MODE = "auto"
                $script:PUBLIC_IP = ""
                Write-Info "Auto-detect mode, will detect public IP on every startup"
                $done = $true
            }
            default {
                Write-Host "Invalid choice, please enter 1, 2 or 3"
            }
        }
    }
}

# Return NAT configuration block based on NAT_MODE, for embedding into start-node.ps1
function Get-NatSection {
    switch ($script:NAT_MODE) {
        "extip" {
            return @"
# Static public IP mode
`$NAT_CONFIG = "extip:$($script:PUBLIC_IP)"
Write-Host "NAT config: `$NAT_CONFIG (static public IP)"
"@
        }
        "any" {
            return @"
# NAT environment mode (UPnP/NAT-PMP)
`$NAT_CONFIG = "any"
Write-Host "NAT config: `$NAT_CONFIG (automatic port mapping)"
"@
        }
        default {
            return @'
# Auto-detect public IP
function Get-PublicIp {
    foreach ($svc in @("https://ip.sb", "https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com", "https://ipecho.net/plain", "https://ipinfo.io/ip")) {
        try {
            $ip = (Invoke-WebRequest -Uri $svc -UseBasicParsing -TimeoutSec 5 -UserAgent "curl").Content.Trim()
            if ($ip -match "^\d+\.\d+\.\d+\.\d+$") {
                return $ip
            }
        } catch {
            continue
        }
    }
    return $null
}

Write-Host "Detecting public IP..."
$DETECTED_IP = Get-PublicIp
if ($DETECTED_IP) {
    $NAT_CONFIG = "extip:$DETECTED_IP"
    Write-Host "  Detected public IP: $DETECTED_IP"
    Write-Host "  NAT config: $NAT_CONFIG"
} else {
    $NAT_CONFIG = "any"
    Write-Host "  Failed to detect public IP, falling back to NAT: any"
}
'@
        }
    }
}

# Optional: reconfigure network
function Reconfigure-Network {
    param([string]$InstallDir)

    Write-Step "6" "Network configuration (optional)"

    Write-Host ""
    Write-Host "This step reconfigures the node's NAT network mode"
    Write-Host "Only needed in the following cases:"
    Write-Host "  - Server IP changed"
    Write-Host "  - Migrated from home network to cloud (or vice versa)"
    Write-Host "  - NAT was misconfigured (e.g. peerCount stays at 0)"
    Write-Host ""

    $reset = Read-Host "Reconfigure network? (y/N)"
    if ($reset -notmatch "^[Yy]$") {
        Write-Info "Skipping network configuration (keeping current settings)"
        return
    }

    $startScript = Join-Path $InstallDir "start-node.ps1"
    if (-not (Test-Path $startScript)) {
        Write-Error "Not found: $startScript"
        Write-Error "Please re-run setup-node-testnet.ps1 to redeploy"
        return
    }

    # Locate start/end indices of the NAT Configuration block
    $content = Get-Content $startScript
    $startIdx = -1
    $endIdx = -1
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match "^# ==================== NAT Configuration ====================$") { $startIdx = $i }
        if ($content[$i] -match "^# ==================== Start Node ====================$") { $endIdx = $i; break }
    }

    if ($startIdx -lt 0 -or $endIdx -lt 0 -or $endIdx -le $startIdx) {
        Write-Error "start-node.ps1 format incompatible (may be generated by an older setup script)"
        Write-Error "Please re-run setup-node-testnet.ps1 to redeploy"
        return
    }

    # Ask for NAT mode
    Choose-NatMode

    # Back up current start-node.ps1
    $backupDir = Join-Path $InstallDir "backup"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupFile = Join-Path $backupDir "start-node.ps1.$timestamp"
    Copy-Item $startScript $backupFile
    Write-Info "Backed up original start-node.ps1 to: $backupFile"

    # Generate the new NAT section and split into lines
    $natSection = Get-NatSection
    $natLines = $natSection -split "`r?`n"

    # Rebuild: [0..startIdx] + new NAT block + [endIdx..end]
    $newContent = @()
    $newContent += $content[0..$startIdx]
    $newContent += $natLines
    $newContent += $content[$endIdx..($content.Count - 1)]
    Set-Content -Path $startScript -Value $newContent

    Write-Success "Network configuration updated to: $($script:NAT_MODE)"
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
    Write-Host "Network Diagnostics:" -ForegroundColor Blue
    Write-Host "  If peerCount stays at 0 after startup, use devp2p to test bootnode connectivity:"
    Write-Host "  devp2p discv4 ping <enode-url>" -ForegroundColor Cyan
    Write-Host "  Example: devp2p discv4 ping enode://6f05...fb@54.169.152.20:30303"
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
    Reconfigure-Network -InstallDir $installDir

    Show-Completion -InstallDir $installDir
}

# Run main process
Main
