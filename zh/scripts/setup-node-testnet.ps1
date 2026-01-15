# ============================================================
# PIJS 共识节点一键部署脚本 (Windows PowerShell)
# ============================================================

#Requires -Version 5.1

# ==================== 配置区域 ====================
$GITHUB_RELEASE = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6h"
$GETH_VERSION = "v1.25.6h"
$GENESIS_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/genesis.json"
$BOOTNODE_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/bootnodes.txt"

$CHAIN_ID = "20250521"
$NETWORK_NAME = "PIJS Testnet"

$DEFAULT_INSTALL_DIR = "$PSScriptRoot\pijs-node"

# ==================== 工具函数 ====================

function Write-Banner {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "        PIJS 共识节点一键部署脚本 (Windows)" -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host ""
}

function Write-Step {
    param([int]$Number, [string]$Message)
    Write-Host ""
    Write-Host "[步骤 $Number] " -ForegroundColor Green -NoNewline
    Write-Host $Message
    Write-Host "------------------------------------------------------------"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[信息] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[警告] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[错误] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[成功] " -ForegroundColor Green -NoNewline
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

# ==================== 安装流程 ====================

function Test-Dependencies {
    Write-Step 1 "检查系统依赖"

    # 检查 PowerShell 版本
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Error-Custom "需要 PowerShell 5.0 或更高版本"
        exit 1
    }

    Write-Success "系统依赖检查通过"
}

function Initialize-Directories {
    Write-Step 2 "创建目录结构"

    $promptDir = Read-Host "请输入安装目录 [默认: $DEFAULT_INSTALL_DIR]"
    if ([string]::IsNullOrWhiteSpace($promptDir)) {
        $script:INSTALL_DIR = $DEFAULT_INSTALL_DIR
    } else {
        $script:INSTALL_DIR = $promptDir
    }

    # 检查是否存在数据
    $chaindata = Join-Path $INSTALL_DIR "data\PIJSChain\chaindata"
    if (Test-Path $chaindata) {
        Write-Warn "检测到已存在的节点数据: $INSTALL_DIR\data"
        $confirm = Read-Host "是否继续？这将保留现有数据 (y/n)"
        if ($confirm -notmatch "^[Yy]$") {
            Write-Host "已取消"
            exit 0
        }
    }

    # 创建目录
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
    Write-Success "目录创建完成: $INSTALL_DIR"
}

function Get-GethBinary {
    Write-Step 3 "下载节点程序"

    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    $platform = "windows-$arch"
    $gethTar = "geth-$GETH_VERSION-$platform.tar.gz"
    $gethUrl = "$GITHUB_RELEASE/$gethTar"

    if (Test-GethInstalled) {
        $version = (geth version 2>$null | Select-Object -First 1)
        Write-Info "检测到已安装的 geth: $version"
        $redownload = Read-Host "是否重新下载最新版本? (y/n) [默认: n]"
        if ($redownload -notmatch "^[Yy]$") {
            Write-Info "跳过下载，使用现有版本"
            return
        }
    }

    Write-Info "正在下载 geth ($platform)..."
    Write-Info "下载地址: $gethUrl"

    $downloadPath = Join-Path $INSTALL_DIR $gethTar

    # 下载文件
    if (-not (Test-Path $downloadPath)) {
        try {
            Invoke-WebRequest -Uri $gethUrl -OutFile $downloadPath -UseBasicParsing
            Write-Success "下载完成"
        } catch {
            Write-Error-Custom "下载失败: $_"
            exit 1
        }
    } else {
        Write-Info "发现已下载的文件，跳过下载"
    }

    # 解压（需要 tar 命令，Windows 10+ 自带）
    Write-Info "解压文件..."
    Set-Location $INSTALL_DIR
    tar -xzf $gethTar

    # 创建 bin 目录
    $binDir = Join-Path $INSTALL_DIR "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # 移动二进制文件
    $binaries = @("geth.exe", "bootnode.exe", "abigen.exe", "clef.exe", "evm.exe", "rlpdump.exe")
    foreach ($binary in $binaries) {
        $sourcePath = Join-Path $INSTALL_DIR $binary
        if (Test-Path $sourcePath) {
            Move-Item $sourcePath $binDir -Force
            Write-Info "已安装: $binary"
        }
    }

    # 清理压缩包
    Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue

    # 添加到 PATH
    Write-Info "配置环境变量..."
    $env:PATH = "$binDir;$env:PATH"

    # 永久添加到用户 PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*pijs-node\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$binDir;$currentPath", "User")
        Write-Info "已添加到系统 PATH"
    }

    # 验证安装
    $gethPath = Join-Path $binDir "geth.exe"
    if (Test-Path $gethPath) {
        & $gethPath version
        Write-Success "节点程序安装完成"
        Write-Info "二进制文件位置: $binDir"
        Write-Warn "请重新打开 PowerShell 窗口使环境变量生效"
    } else {
        Write-Error-Custom "geth 安装失败"
        exit 1
    }
}

function Get-GenesisConfig {
    Write-Step 4 "下载创世配置"

    $genesisPath = Join-Path $INSTALL_DIR "genesis.json"

    if (Test-Path $genesisPath) {
        Write-Info "检测到已存在的 genesis.json"
        $redownload = Read-Host "是否重新下载? (y/n) [默认: n]"
        if ($redownload -notmatch "^[Yy]$") {
            Write-Info "跳过下载，使用现有配置"
            return
        }
    }

    Write-Info "正在下载 genesis.json..."
    Write-Info "下载地址: $GENESIS_URL"

    # 尝试自动下载
    try {
        Invoke-WebRequest -Uri $GENESIS_URL -OutFile $genesisPath -UseBasicParsing
        Write-Success "genesis.json 下载完成"
    } catch {
        # 下载失败，提示手动下载
        Write-Host ""
        Write-Warn "自动下载失败，请手动下载 genesis.json"
        Write-Info "下载地址: $GENESIS_URL"
        Write-Info "保存到: $genesisPath"
        Write-Host ""

        $genesisReady = Read-Host "genesis.json 是否已准备好? (y/n)"
        if ($genesisReady -notmatch "^[Yy]$") {
            Write-Error-Custom "请先下载 genesis.json 后再运行此脚本"
            exit 1
        }

        if (-not (Test-Path $genesisPath)) {
            Write-Error-Custom "genesis.json 文件不存在"
            exit 1
        }
    }

    Write-Success "创世配置就绪"
}

function New-Nodekey {
    Write-Step 5 "生成节点身份 (nodekey)"

    $nodekeyPath = Join-Path $INSTALL_DIR "data\PIJSChain\nodekey"
    $nodekeyDir = Join-Path $INSTALL_DIR "data\PIJSChain"
    $bootnodePath = Join-Path $INSTALL_DIR "bin\bootnode.exe"

    # 确保目录存在
    if (-not (Test-Path $nodekeyDir)) {
        New-Item -ItemType Directory -Path $nodekeyDir -Force | Out-Null
    }

    if (Test-Path $nodekeyPath) {
        Write-Info "检测到已存在的 nodekey"
        $keepNodekey = Read-Host "是否保留现有 nodekey? (y/n) [默认: y]"
        if ($keepNodekey -match "^[Nn]$") {
            Remove-Item $nodekeyPath -Force
        } else {
            Write-Info "保留现有 nodekey"
            # 显示现有 enode 地址
            if (Test-Path $bootnodePath) {
                $enodeAddr = & $bootnodePath -nodekey $nodekeyPath -writeaddress 2>$null
                if ($enodeAddr) {
                    Write-Info "节点 ID: $enodeAddr"
                }
            }
            return
        }
    }

    Write-Info "生成新的 nodekey..."

    # 优先使用 bootnode 工具生成
    if (Test-Path $bootnodePath) {
        & $bootnodePath -genkey $nodekeyPath
        Write-Success "nodekey 已生成 (使用 bootnode)"
        # 显示 enode 地址
        $enodeAddr = & $bootnodePath -nodekey $nodekeyPath -writeaddress 2>$null
        if ($enodeAddr) {
            Write-Info "节点 ID: $enodeAddr"
        }
    } else {
        # 备用方案：生成 32 字节随机数
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $nodekey = [BitConverter]::ToString($bytes) -replace '-', ''
        Set-Content -Path $nodekeyPath -Value $nodekey.ToLower() -NoNewline
        Write-Success "nodekey 已生成 (使用随机数)"
    }

    Write-Info "nodekey 位置: $nodekeyPath"
    Write-Warn "请妥善备份此文件，它决定了您的节点身份"
}

function New-BLSKey {
    Write-Step 6 "生成 BLS 密钥"

    $blsKeyfile = Join-Path $INSTALL_DIR "keys\bls-keystore.json"
    $blsPassword = Join-Path $INSTALL_DIR "keys\password.txt"

    if (Test-Path $blsKeyfile) {
        Write-Info "检测到已存在的 BLS 密钥"
        $keepBls = Read-Host "是否保留现有 BLS 密钥? (y/n) [默认: y]"
        if ($keepBls -match "^[Nn]$") {
            Remove-Item $blsKeyfile -Force -ErrorAction SilentlyContinue
            Remove-Item $blsPassword -Force -ErrorAction SilentlyContinue
        } else {
            Write-Info "保留现有 BLS 密钥"
            return
        }
    }

    Write-Host ""
    Write-Info "即将生成 BLS 密钥，请设置一个强密码"
    Write-Warn "此密码用于加密您的 BLS 私钥，请务必牢记！"
    Write-Host ""

    # 获取密码
    while ($true) {
        $blsPwd = Read-Host "请输入 BLS 密钥密码" -AsSecureString
        $blsPwdConfirm = Read-Host "请再次输入密码确认" -AsSecureString

        $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($blsPwd))
        $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($blsPwdConfirm))

        if ($pwd1 -ne $pwd2) {
            Write-Error-Custom "两次输入的密码不一致，请重试"
            continue
        }

        if ($pwd1.Length -lt 8) {
            Write-Error-Custom "密码长度至少需要 8 个字符"
            continue
        }

        $script:BLS_PWD = $pwd1
        break
    }

    # 保存密码到文件
    Set-Content -Path $blsPassword -Value $BLS_PWD -NoNewline

    # 生成 BLS 密钥
    Write-Info "正在生成 BLS 密钥..."

    & geth hybrid bls generate --save $blsKeyfile --password $blsPassword

    if (-not (Test-Path $blsKeyfile)) {
        Write-Error-Custom "BLS 密钥生成失败"
        exit 1
    }

    Write-Host ""
    Write-Success "BLS 密钥生成成功"
    Write-Info "密钥文件: $blsKeyfile"
    Write-Info "密码文件: $blsPassword"
    Write-Host ""
    Write-Info "您的 BLS 公钥:"
    & geth hybrid bls show --keyfile $blsKeyfile --password $blsPassword
    Write-Host ""
    Write-Warn "请妥善备份 BLS 密钥文件和密码，丢失后无法恢复！"
}

function Initialize-Blockchain {
    Write-Step 7 "初始化区块链数据"

    $chaindata = Join-Path $INSTALL_DIR "data\PIJSChain\chaindata"
    $genesisPath = Join-Path $INSTALL_DIR "genesis.json"

    if ((Test-Path $chaindata) -and (Get-ChildItem $chaindata -ErrorAction SilentlyContinue)) {
        Write-Info "检测到已初始化的区块链数据"
        $skipInit = Read-Host "是否跳过初始化? (y/n) [默认: y]"
        if ($skipInit -notmatch "^[Nn]$") {
            Write-Info "跳过初始化"
            return
        }
        Write-Warn "重新初始化将删除现有数据！"
        $confirmDelete = Read-Host "确认删除并重新初始化? (yes/no)"
        if ($confirmDelete -ne "yes") {
            Write-Info "取消重新初始化"
            return
        }
        Remove-Item (Join-Path $INSTALL_DIR "data\PIJSChain\chaindata") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $INSTALL_DIR "data\PIJSChain\lightchaindata") -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Info "正在初始化区块链数据..."
    $datadir = Join-Path $INSTALL_DIR "data"
    & geth init --datadir $datadir $genesisPath

    Write-Success "区块链数据初始化完成"
}

function Set-WithdrawalAddress {
    Write-Step 8 "配置提款地址"

    Write-Host ""
    Write-Info "提款地址用于接收您的质押奖励"
    Write-Warn "请确保您完全控制此地址的私钥"
    Write-Host ""

    while ($true) {
        $addr = Read-Host "请输入您的提款地址 (0x 开头)"

        if ($addr -notmatch "^0x[a-fA-F0-9]{40}$") {
            Write-Error-Custom "地址格式不正确，请输入有效的以太坊地址"
            continue
        }

        $confirm = Read-Host "确认提款地址: $addr (y/n)"
        if ($confirm -match "^[Yy]$") {
            $script:WITHDRAWAL_ADDRESS = $addr
            break
        }
    }

    Write-Success "提款地址已配置: $WITHDRAWAL_ADDRESS"
}

function Get-Bootnodes {
    Write-Step 9 "配置引导节点"

    # 默认引导节点
    $defaultBootnodes = "enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303,enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303,enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303"

    Write-Host ""
    Write-Info "引导节点用于连接到 PIJS 网络"
    Write-Host ""

    # 尝试下载 bootnodes.txt
    Write-Info "正在获取引导节点列表..."
    $bootnodesPath = Join-Path $INSTALL_DIR "bootnodes.txt"

    try {
        Invoke-WebRequest -Uri $BOOTNODE_URL -OutFile $bootnodesPath -UseBasicParsing
        # 读取 bootnodes.txt 并合并为逗号分隔的字符串
        $bootnodesContent = Get-Content $bootnodesPath | Where-Object { $_ -notmatch "^#" -and $_ -ne "" }
        if ($bootnodesContent) {
            $script:BOOTNODES = ($bootnodesContent -join ",")
            Write-Success "已从 bootnodes.txt 获取引导节点"
        } else {
            $script:BOOTNODES = $defaultBootnodes
            Write-Info "使用默认引导节点"
        }
    } catch {
        $script:BOOTNODES = $defaultBootnodes
        Write-Info "使用默认引导节点"
    }

    Write-Success "引导节点已配置"
}

function New-StartScript {
    Write-Step 10 "生成启动脚本"

    $startScript = Join-Path $INSTALL_DIR "start-node.ps1"

    $scriptContent = @"
# PIJS 节点启动脚本 (Windows)
# 生成时间: $(Get-Date)

# ==================== 配置 ====================
`$INSTALL_DIR = "$INSTALL_DIR"
`$DATADIR = "`$INSTALL_DIR\data"
`$BLS_KEYFILE = "`$INSTALL_DIR\keys\bls-keystore.json"
`$BLS_PASSWORD = "`$INSTALL_DIR\keys\password.txt"
`$WITHDRAWAL_ADDRESS = "$WITHDRAWAL_ADDRESS"
`$BOOTNODES = "$BOOTNODES"

# 网络配置
`$NETWORK_ID = "$CHAIN_ID"
`$HTTP_ADDR = "0.0.0.0"
`$HTTP_PORT = "8545"
# 安全警告：仅暴露安全的 API 模块！
# 安全：eth,net,web3,hybrid
# 危险（绝不可添加）：personal,admin,debug,miner
`$HTTP_API = "eth,net,web3,hybrid"
`$WS_ADDR = "0.0.0.0"
`$WS_PORT = "8546"
# 安全警告：同 HTTP_API，不要添加 personal/admin/debug/miner
`$WS_API = "eth,net,web3,hybrid"

# 性能配置
`$CACHE_SIZE = "4096"

# 日志配置
`$LOG_DIR = "`$INSTALL_DIR\logs"
`$LOG_FILE = "`$LOG_DIR\geth.log"

# ==================== 启动检查 ====================
Write-Host "========================================"
Write-Host "  PIJS 共识节点启动"
Write-Host "========================================"

if (-not (Test-Path `$BLS_KEYFILE)) {
    Write-Host "错误: BLS 密钥文件不存在: `$BLS_KEYFILE" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path `$BLS_PASSWORD)) {
    Write-Host "错误: BLS 密码文件不存在: `$BLS_PASSWORD" -ForegroundColor Red
    exit 1
}

# 创建日志目录
if (-not (Test-Path `$LOG_DIR)) {
    New-Item -ItemType Directory -Path `$LOG_DIR -Force | Out-Null
}

# 显示配置信息
Write-Host ""
Write-Host "配置信息:"
Write-Host "  数据目录: `$DATADIR"
Write-Host "  网络 ID: `$NETWORK_ID"
Write-Host "  HTTP RPC: http://`${HTTP_ADDR}:`$HTTP_PORT"
Write-Host "  WebSocket: ws://`${WS_ADDR}:`$WS_PORT"
Write-Host "  提款地址: `$WITHDRAWAL_ADDRESS"
Write-Host "  日志文件: `$LOG_FILE"
Write-Host ""

# 安全警告
if (`$HTTP_ADDR -eq "0.0.0.0" -or `$WS_ADDR -eq "0.0.0.0") {
    Write-Host "========================================"
    Write-Host "安全警告: RPC 接口对外暴露" -ForegroundColor Yellow
    Write-Host "========================================"
    Write-Host "建议配置防火墙限制访问 IP"
    Write-Host ""
}

# ==================== 启动节点 ====================
Write-Host "正在启动节点..."

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

    # 生成停止脚本
    $stopScript = Join-Path $INSTALL_DIR "stop-node.ps1"
    $stopContent = @"
# PIJS 节点停止脚本

Write-Host "正在停止节点..."
Get-Process -Name "geth" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "节点已停止"
"@
    Set-Content -Path $stopScript -Value $stopContent

    Write-Success "启动脚本已生成:"
    Write-Host "  - 启动节点: $startScript"
    Write-Host "  - 停止节点: $stopScript"
}

function Show-Completion {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "        部署完成！" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "节点信息:" -ForegroundColor Blue
    Write-Host "  安装目录: $INSTALL_DIR"
    Write-Host "  数据目录: $INSTALL_DIR\data"
    Write-Host "  BLS 密钥: $INSTALL_DIR\keys\bls-keystore.json"
    Write-Host "  提款地址: $WITHDRAWAL_ADDRESS"
    Write-Host ""
    Write-Host "启动命令:" -ForegroundColor Blue
    Write-Host "  启动节点: .\start-node.ps1"
    Write-Host "  停止节点: .\stop-node.ps1"
    Write-Host ""
    Write-Host "下一步操作:" -ForegroundColor Blue
    Write-Host "  1. 启动节点: cd $INSTALL_DIR; .\start-node.ps1"
    Write-Host "  2. 等待节点同步完成"
    Write-Host "  3. 生成质押签名:"
    Write-Host "     geth hybrid bls deposit --keyfile .\keys\bls-keystore.json ``"
    Write-Host "       --chainid $CHAIN_ID --address $WITHDRAWAL_ADDRESS --amount 10000 ``"
    Write-Host "       --output deposit_data.json"
    Write-Host "  4. 访问质押平台，上传 deposit_data.json 完成质押"
    Write-Host ""
    Write-Host "重要提示:" -ForegroundColor Yellow
    Write-Host "  - 请妥善备份 $INSTALL_DIR\keys\ 目录下的密钥文件"
    Write-Host "  - 请妥善备份 $INSTALL_DIR\data\PIJSChain\nodekey 文件"
    Write-Host "  - 首次同步可能需要数小时到数天（归档模式）"
    Write-Host ""
    Write-Host "============================================================"
}

# ==================== 主流程 ====================

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

# 运行主流程
Main
