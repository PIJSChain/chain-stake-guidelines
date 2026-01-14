# ============================================================
# PIJS Consensus Node One-Click Deployment Script (Windows PowerShell)
# ============================================================

#Requires -Version 5.1

# ==================== Configuration ====================
$GITHUB_RELEASE = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6h"
$GETH_VERSION = "v1.25.6h"
$GENESIS_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/genesis.json"
$BOOTNODE_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/bootnodes.txt"

$CHAIN_ID = "20250521"
$NETWORK_NAME = "PIJS Testnet"

$DEFAULT_INSTALL_DIR = "$env:USERPROFILE\pijs-node"

# ==================== Utility Functions ====================

function Write-Banner {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "    PIJS Consensus Node One-Click Deployment (Windows)" -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host ""
}

function Write-Step {
    param([int]$Number, [string]$Message)
    Write-Host ""
    Write-Host "[Step $Number] " -ForegroundColor Green -NoNewline
    Write-Host $Message
    Write-Host "------------------------------------------------------------"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Test-GethInstalled {
    try {
        $null = Get-Command geth -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# ==================== Installation Process ====================

function Test-Dependencies {
    Write-Step 1 "Checking system dependencies"

    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Error-Custom "PowerShell 5.0 or higher is required"
        exit 1
    }

    Write-Success "System dependencies check passed"
}

function Initialize-Directories {
    Write-Step 2 "Creating directory structure"

    $promptDir = Read-Host "Enter installation directory [default: $DEFAULT_INSTALL_DIR]"
    if ([string]::IsNullOrWhiteSpace($promptDir)) {
        $script:INSTALL_DIR = $DEFAULT_INSTALL_DIR
    } else {
        $script:INSTALL_DIR = $promptDir
    }

    # Check if data exists
    $chaindata = Join-Path $INSTALL_DIR "data\PIJSChain\chaindata"
    if (Test-Path $chaindata) {
        Write-Warn "Existing node data detected: $INSTALL_DIR\data"
        $confirm = Read-Host "Continue? This will preserve existing data (y/n)"
        if ($confirm -notmatch "^[Yy]$") {
            Write-Host "Cancelled"
            exit 0
        }
    }

    # Create directories
    $dirs = @(
        (Join-Path $INSTALL_DIR "data\PIJSChain"),
        (Join-Path $INSTALL_DIR "logs"),
        (Join-Path $INSTALL_DIR "keys")
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Set-Location $INSTALL_DIR
    Write-Success "Directories created: $INSTALL_DIR"
}

function Get-GethBinary {
    Write-Step 3 "Downloading node program"

    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    $platform = "windows-$arch"
    $gethTar = "geth-$GETH_VERSION-$platform.tar.gz"
    $gethUrl = "$GITHUB_RELEASE/$gethTar"

    if (Test-GethInstalled) {
        $version = (geth version 2>$null | Select-Object -First 1)
        Write-Info "Detected installed geth: $version"
        $redownload = Read-Host "Download latest version? (y/n) [default: n]"
        if ($redownload -notmatch "^[Yy]$") {
            Write-Info "Skipping download, using existing version"
            return
        }
    }

    Write-Info "Downloading geth ($platform)..."
    Write-Info "URL: $gethUrl"

    $downloadPath = Join-Path $INSTALL_DIR $gethTar

    # Download file
    if (-not (Test-Path $downloadPath)) {
        try {
            Invoke-WebRequest -Uri $gethUrl -OutFile $downloadPath -UseBasicParsing
            Write-Success "Download complete"
        } catch {
            Write-Error-Custom "Download failed: $_"
            exit 1
        }
    } else {
        Write-Info "Found downloaded file, skipping download"
    }

    # Extract (requires tar command, built-in on Windows 10+)
    Write-Info "Extracting files..."
    Set-Location $INSTALL_DIR
    tar -xzf $gethTar

    # Create bin directory
    $binDir = Join-Path $INSTALL_DIR "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # Move binary files
    $binaries = @("geth.exe", "bootnode.exe", "abigen.exe", "clef.exe", "evm.exe", "rlpdump.exe")
    foreach ($binary in $binaries) {
        $sourcePath = Join-Path $INSTALL_DIR $binary
        if (Test-Path $sourcePath) {
            Move-Item $sourcePath $binDir -Force
            Write-Info "Installed: $binary"
        }
    }

    # Clean up archive
    Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue

    # Add to PATH
    Write-Info "Configuring environment variables..."
    $env:PATH = "$binDir;$env:PATH"

    # Permanently add to user PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*pijs-node\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$binDir;$currentPath", "User")
        Write-Info "Added to system PATH"
    }

    # Verify installation
    $gethPath = Join-Path $binDir "geth.exe"
    if (Test-Path $gethPath) {
        & $gethPath version
        Write-Success "Node program installation complete"
        Write-Info "Binary location: $binDir"
        Write-Warn "Please reopen PowerShell window for environment variables to take effect"
    } else {
        Write-Error-Custom "geth installation failed"
        exit 1
    }
}

function Get-GenesisConfig {
    Write-Step 4 "Downloading genesis configuration"

    $genesisPath = Join-Path $INSTALL_DIR "genesis.json"

    if (Test-Path $genesisPath) {
        Write-Info "Existing genesis.json detected"
        $redownload = Read-Host "Re-download? (y/n) [default: n]"
        if ($redownload -notmatch "^[Yy]$") {
            Write-Info "Skipping download, using existing configuration"
            return
        }
    }

    Write-Info "Downloading genesis.json..."
    Write-Info "URL: $GENESIS_URL"

    # Try auto download
    try {
        Invoke-WebRequest -Uri $GENESIS_URL -OutFile $genesisPath -UseBasicParsing
        Write-Success "genesis.json download complete"
    } catch {
        # Download failed, prompt for manual download
        Write-Host ""
        Write-Warn "Auto download failed, please download genesis.json manually"
        Write-Info "URL: $GENESIS_URL"
        Write-Info "Save to: $genesisPath"
        Write-Host ""

        $genesisReady = Read-Host "Is genesis.json ready? (y/n)"
        if ($genesisReady -notmatch "^[Yy]$") {
            Write-Error-Custom "Please download genesis.json before running this script"
            exit 1
        }

        if (-not (Test-Path $genesisPath)) {
            Write-Error-Custom "genesis.json file does not exist"
            exit 1
        }
    }

    Write-Success "Genesis configuration ready"
}

function New-Nodekey {
    Write-Step 5 "Generating node identity (nodekey)"

    $nodekeyPath = Join-Path $INSTALL_DIR "data\PIJSChain\nodekey"
    $nodekeyDir = Join-Path $INSTALL_DIR "data\PIJSChain"
    $bootnodePath = Join-Path $INSTALL_DIR "bin\bootnode.exe"

    # Ensure directory exists
    if (-not (Test-Path $nodekeyDir)) {
        New-Item -ItemType Directory -Path $nodekeyDir -Force | Out-Null
    }

    if (Test-Path $nodekeyPath) {
        Write-Info "Existing nodekey detected"
        $keepNodekey = Read-Host "Keep existing nodekey? (y/n) [default: y]"
        if ($keepNodekey -match "^[Nn]$") {
            Remove-Item $nodekeyPath -Force
        } else {
            Write-Info "Keeping existing nodekey"
            # Show existing enode address
            if (Test-Path $bootnodePath) {
                $enodeAddr = & $bootnodePath -nodekey $nodekeyPath -writeaddress 2>$null
                if ($enodeAddr) {
                    Write-Info "Node ID: $enodeAddr"
                }
            }
            return
        }
    }

    Write-Info "Generating new nodekey..."

    # Prefer bootnode tool for generation
    if (Test-Path $bootnodePath) {
        & $bootnodePath -genkey $nodekeyPath
        Write-Success "nodekey generated (using bootnode)"
        # Show enode address
        $enodeAddr = & $bootnodePath -nodekey $nodekeyPath -writeaddress 2>$null
        if ($enodeAddr) {
            Write-Info "Node ID: $enodeAddr"
        }
    } else {
        # Fallback: generate 32-byte random number
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $nodekey = [BitConverter]::ToString($bytes) -replace '-', ''
        Set-Content -Path $nodekeyPath -Value $nodekey.ToLower() -NoNewline
        Write-Success "nodekey generated (using random)"
    }

    Write-Info "nodekey location: $nodekeyPath"
    Write-Warn "Please backup this file securely, it determines your node identity"
}

function New-BLSKey {
    Write-Step 6 "Generating BLS key"

    $blsKeyfile = Join-Path $INSTALL_DIR "keys\bls-keystore.json"
    $blsPassword = Join-Path $INSTALL_DIR "keys\password.txt"

    if (Test-Path $blsKeyfile) {
        Write-Info "Existing BLS key detected"
        $keepBls = Read-Host "Keep existing BLS key? (y/n) [default: y]"
        if ($keepBls -match "^[Nn]$") {
            Remove-Item $blsKeyfile -Force -ErrorAction SilentlyContinue
            Remove-Item $blsPassword -Force -ErrorAction SilentlyContinue
        } else {
            Write-Info "Keeping existing BLS key"
            return
        }
    }

    Write-Host ""
    Write-Info "About to generate BLS key, please set a strong password"
    Write-Warn "This password encrypts your BLS private key, remember it!"
    Write-Host ""

    # Get password
    while ($true) {
        $blsPwd = Read-Host "Enter BLS key password" -AsSecureString
        $blsPwdConfirm = Read-Host "Confirm password" -AsSecureString

        $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($blsPwd))
        $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($blsPwdConfirm))

        if ($pwd1 -ne $pwd2) {
            Write-Error-Custom "Passwords do not match, please try again"
            continue
        }

        if ($pwd1.Length -lt 8) {
            Write-Error-Custom "Password must be at least 8 characters"
            continue
        }

        $script:BLS_PWD = $pwd1
        break
    }

    # Save password to file
    Set-Content -Path $blsPassword -Value $BLS_PWD -NoNewline

    # Generate BLS key
    Write-Info "Generating BLS key..."

    & geth hybrid bls generate --save $blsKeyfile --password $blsPassword

    if (-not (Test-Path $blsKeyfile)) {
        Write-Error-Custom "BLS key generation failed"
        exit 1
    }

    Write-Host ""
    Write-Success "BLS key generated successfully"
    Write-Info "Key file: $blsKeyfile"
    Write-Info "Password file: $blsPassword"
    Write-Host ""
    Write-Info "Your BLS public key:"
    & geth hybrid bls show --keyfile $blsKeyfile --password $blsPassword
    Write-Host ""
    Write-Warn "Please backup BLS key file and password securely, cannot be recovered if lost!"
}

function Initialize-Blockchain {
    Write-Step 7 "Initializing blockchain data"

    $chaindata = Join-Path $INSTALL_DIR "data\PIJSChain\chaindata"
    $genesisPath = Join-Path $INSTALL_DIR "genesis.json"

    if ((Test-Path $chaindata) -and (Get-ChildItem $chaindata -ErrorAction SilentlyContinue)) {
        Write-Info "Existing blockchain data detected"
        $skipInit = Read-Host "Skip initialization? (y/n) [default: y]"
        if ($skipInit -notmatch "^[Nn]$") {
            Write-Info "Skipping initialization"
            return
        }
        Write-Warn "Re-initialization will delete existing data!"
        $confirmDelete = Read-Host "Confirm delete and re-initialize? (yes/no)"
        if ($confirmDelete -ne "yes") {
            Write-Info "Cancelled re-initialization"
            return
        }
        Remove-Item (Join-Path $INSTALL_DIR "data\PIJSChain\chaindata") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $INSTALL_DIR "data\PIJSChain\lightchaindata") -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Info "Initializing blockchain data..."
    $datadir = Join-Path $INSTALL_DIR "data"
    & geth init --datadir $datadir $genesisPath

    Write-Success "Blockchain data initialization complete"
}

function Set-WithdrawalAddress {
    Write-Step 8 "Configuring withdrawal address"

    Write-Host ""
    Write-Info "Withdrawal address receives your staking rewards"
    Write-Warn "Ensure you have full control of this address's private key"
    Write-Host ""

    while ($true) {
        $addr = Read-Host "Enter your withdrawal address (starting with 0x)"

        if ($addr -notmatch "^0x[a-fA-F0-9]{40}$") {
            Write-Error-Custom "Invalid address format, please enter a valid Ethereum address"
            continue
        }

        $confirm = Read-Host "Confirm withdrawal address: $addr (y/n)"
        if ($confirm -match "^[Yy]$") {
            $script:WITHDRAWAL_ADDRESS = $addr
            break
        }
    }

    Write-Success "Withdrawal address configured: $WITHDRAWAL_ADDRESS"
}

function Get-Bootnodes {
    Write-Step 9 "Configuring boot nodes"

    # Default boot nodes
    $defaultBootnodes = "enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303,enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303,enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303"

    Write-Host ""
    Write-Info "Boot nodes are used to connect to the PIJS network"
    Write-Host ""

    # Try to download bootnodes.txt
    Write-Info "Fetching boot node list..."
    $bootnodesPath = Join-Path $INSTALL_DIR "bootnodes.txt"

    try {
        Invoke-WebRequest -Uri $BOOTNODE_URL -OutFile $bootnodesPath -UseBasicParsing
        # Read bootnodes.txt and merge into comma-separated string
        $bootnodesContent = Get-Content $bootnodesPath | Where-Object { $_ -notmatch "^#" -and $_ -ne "" }
        if ($bootnodesContent) {
            $script:BOOTNODES = ($bootnodesContent -join ",")
            Write-Success "Boot nodes fetched from bootnodes.txt"
        } else {
            $script:BOOTNODES = $defaultBootnodes
            Write-Info "Using default boot nodes"
        }
    } catch {
        $script:BOOTNODES = $defaultBootnodes
        Write-Info "Using default boot nodes"
    }

    Write-Success "Boot nodes configured"
}

function New-StartScript {
    Write-Step 10 "Generating startup scripts"

    $startScript = Join-Path $INSTALL_DIR "start-node.ps1"

    $scriptContent = @"
# PIJS Node Startup Script (Windows)
# Generated: $(Get-Date)

# ==================== Configuration ====================
`$INSTALL_DIR = "$INSTALL_DIR"
`$DATADIR = "`$INSTALL_DIR\data"
`$BLS_KEYFILE = "`$INSTALL_DIR\keys\bls-keystore.json"
`$BLS_PASSWORD = "`$INSTALL_DIR\keys\password.txt"
`$WITHDRAWAL_ADDRESS = "$WITHDRAWAL_ADDRESS"
`$BOOTNODES = "$BOOTNODES"

# Network configuration
`$NETWORK_ID = "$CHAIN_ID"
`$HTTP_ADDR = "0.0.0.0"
`$HTTP_PORT = "8545"
# Security warning: Only expose safe API modules!
# Safe: eth,net,web3,hybrid
# Dangerous (never add): personal,admin,debug,miner
`$HTTP_API = "eth,net,web3,hybrid"
`$WS_ADDR = "0.0.0.0"
`$WS_PORT = "8546"
# Security warning: Same as HTTP_API, do not add personal/admin/debug/miner
`$WS_API = "eth,net,web3,hybrid"

# Performance configuration
`$CACHE_SIZE = "4096"

# Log configuration
`$LOG_DIR = "`$INSTALL_DIR\logs"
`$LOG_FILE = "`$LOG_DIR\geth.log"

# ==================== Startup Checks ====================
Write-Host "========================================"
Write-Host "  PIJS Consensus Node Starting"
Write-Host "========================================"

if (-not (Test-Path `$BLS_KEYFILE)) {
    Write-Host "Error: BLS key file does not exist: `$BLS_KEYFILE" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path `$BLS_PASSWORD)) {
    Write-Host "Error: BLS password file does not exist: `$BLS_PASSWORD" -ForegroundColor Red
    exit 1
}

# Create log directory
if (-not (Test-Path `$LOG_DIR)) {
    New-Item -ItemType Directory -Path `$LOG_DIR -Force | Out-Null
}

# Display configuration
Write-Host ""
Write-Host "Configuration:"
Write-Host "  Data directory: `$DATADIR"
Write-Host "  Network ID: `$NETWORK_ID"
Write-Host "  HTTP RPC: http://`${HTTP_ADDR}:`$HTTP_PORT"
Write-Host "  WebSocket: ws://`${WS_ADDR}:`$WS_PORT"
Write-Host "  Withdrawal address: `$WITHDRAWAL_ADDRESS"
Write-Host "  Log file: `$LOG_FILE"
Write-Host ""

# Security warning
if (`$HTTP_ADDR -eq "0.0.0.0" -or `$WS_ADDR -eq "0.0.0.0") {
    Write-Host "========================================"
    Write-Host "Security Warning: RPC interface exposed externally" -ForegroundColor Yellow
    Write-Host "========================================"
    Write-Host "Recommend configuring firewall to restrict access IPs"
    Write-Host ""
}

# ==================== Start Node ====================
Write-Host "Starting node..."

`$args = @(
    "--datadir", `$DATADIR,
    "--networkid", `$NETWORK_ID,
    "--syncmode", "full",
    "--gcmode", "archive",
    "--cache", `$CACHE_SIZE,
    "--http",
    "--http.addr", `$HTTP_ADDR,
    "--http.port", `$HTTP_PORT,
    "--http.api", `$HTTP_API,
    "--http.corsdomain", "*",
    "--http.vhosts", "*",
    "--ws",
    "--ws.addr", `$WS_ADDR,
    "--ws.port", `$WS_PORT,
    "--ws.api", `$WS_API,
    "--ws.origins", "*",
    "--authrpc.vhosts", "*",
    "--hybrid.liveness",
    "--hybrid.withdrawal", `$WITHDRAWAL_ADDRESS,
    "--hybrid.blskey", `$BLS_KEYFILE,
    "--hybrid.blspassword", `$BLS_PASSWORD,
    "--bootnodes", `$BOOTNODES,
    "--log.file", `$LOG_FILE,
    "--log.maxsize", "100",
    "--log.maxbackups", "10",
    "--log.compress",
    "--nat", "any"
)

& geth @args
"@

    Set-Content -Path $startScript -Value $scriptContent

    # Generate stop script
    $stopScript = Join-Path $INSTALL_DIR "stop-node.ps1"
    $stopContent = @"
# PIJS Node Stop Script

Write-Host "Stopping node..."
Get-Process -Name "geth" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Node stopped"
"@
    Set-Content -Path $stopScript -Value $stopContent

    Write-Success "Startup scripts generated:"
    Write-Host "  - Start node: $startScript"
    Write-Host "  - Stop node: $stopScript"
}

function Show-Completion {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "        Deployment Complete!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Node Information:" -ForegroundColor Blue
    Write-Host "  Install directory: $INSTALL_DIR"
    Write-Host "  Data directory: $INSTALL_DIR\data"
    Write-Host "  BLS key: $INSTALL_DIR\keys\bls-keystore.json"
    Write-Host "  Withdrawal address: $WITHDRAWAL_ADDRESS"
    Write-Host ""
    Write-Host "Startup Commands:" -ForegroundColor Blue
    Write-Host "  Start node: .\start-node.ps1"
    Write-Host "  Stop node: .\stop-node.ps1"
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Blue
    Write-Host "  1. Start node: cd $INSTALL_DIR; .\start-node.ps1"
    Write-Host "  2. Wait for node synchronization to complete"
    Write-Host "  3. Generate staking signature:"
    Write-Host "     geth hybrid bls deposit --keyfile .\keys\bls-keystore.json ``"
    Write-Host "       --chainid $CHAIN_ID --address $WITHDRAWAL_ADDRESS --amount 10000 ``"
    Write-Host "       --output deposit_data.json"
    Write-Host "  4. Visit staking platform, upload deposit_data.json to complete staking"
    Write-Host ""
    Write-Host "Important Notes:" -ForegroundColor Yellow
    Write-Host "  - Please backup key files in $INSTALL_DIR\keys\ directory securely"
    Write-Host "  - Please backup $INSTALL_DIR\data\PIJSChain\nodekey file"
    Write-Host "  - Initial sync may take hours to days (archive mode)"
    Write-Host ""
    Write-Host "============================================================"
}

# ==================== Main Process ====================

function Main {
    Write-Banner

    Test-Dependencies
    Initialize-Directories
    Get-GethBinary
    Get-GenesisConfig
    New-Nodekey
    New-BLSKey
    Initialize-Blockchain
    Set-WithdrawalAddress
    Get-Bootnodes
    New-StartScript

    Show-Completion
}

# Run main process
Main
