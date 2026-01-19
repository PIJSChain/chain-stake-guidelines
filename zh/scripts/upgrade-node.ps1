# ============================================================
# PIJS 共识节点升级脚本 (Windows PowerShell)
# 用于硬分叉升级 - 仅更新客户端和链配置
# 不会删除现有链数据
# ============================================================

$ErrorActionPreference = "Stop"

# ==================== 配置区域 ====================
$GITHUB_RELEASE = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6k"
$GETH_VERSION = "v1.25.6k"
$GENESIS_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json"

# 默认目录
$DEFAULT_INSTALL_DIR = "$env:USERPROFILE\pijs-node"

# ==================== 工具函数 ====================

function Write-Banner {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "    PIJS 共识节点升级脚本" -ForegroundColor Blue
    Write-Host "    目标版本: $GETH_VERSION" -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host ""
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[步骤 $Step] $Message" -ForegroundColor Green
    Write-Host "------------------------------------------------------------"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[信息] $Message" -ForegroundColor Blue
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[警告] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[错误] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[完成] $Message" -ForegroundColor Green
}

# 检查节点是否运行
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
            # 忽略错误
        }
    }
    return $false
}

# 停止运行中的节点
function Stop-Node {
    param([string]$InstallDir)

    Write-Step "1" "检查节点状态"

    if (Test-NodeRunning -InstallDir $InstallDir) {
        Write-Warn "节点正在运行，正在停止..."

        $processes = Get-Process -Name "geth" -ErrorAction SilentlyContinue
        foreach ($proc in $processes) {
            try {
                $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                if ($cmdLine -like "*$InstallDir*") {
                    Stop-Process -Id $proc.Id -Force
                }
            } catch {
                # 忽略错误
            }
        }

        Start-Sleep -Seconds 3

        if (Test-NodeRunning -InstallDir $InstallDir) {
            Write-Error "无法停止节点，请先手动停止"
            exit 1
        }
        Write-Success "节点已停止"
    } else {
        Write-Info "节点未运行"
    }
}

# 备份当前客户端
function Backup-Client {
    param([string]$InstallDir)

    Write-Step "2" "备份当前客户端"

    $backupDir = Join-Path $InstallDir "backup"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $gethPath = Join-Path $InstallDir "bin\geth.exe"
    if (Test-Path $gethPath) {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupName = "geth.backup.$timestamp.exe"
        Copy-Item $gethPath (Join-Path $backupDir $backupName)
        Write-Success "当前客户端已备份至: $backupDir\$backupName"
    } else {
        Write-Info "没有现有客户端需要备份"
    }
}

# 下载新客户端
function Download-Client {
    param([string]$InstallDir)

    Write-Step "3" "下载新客户端 ($GETH_VERSION)"

    $gethFilename = "geth-windows-amd64.exe"
    $downloadUrl = "$GITHUB_RELEASE/$gethFilename"

    Write-Info "下载地址: $downloadUrl"

    $binDir = Join-Path $InstallDir "bin"
    $gethPath = Join-Path $binDir "geth.exe"

    # 删除旧文件
    if (Test-Path $gethPath) {
        Remove-Item $gethPath -Force
    }

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $gethPath -UseBasicParsing
    } catch {
        Write-Error "下载失败: $_"
        exit 1
    }

    # 验证下载
    if (-not (Test-Path $gethPath) -or (Get-Item $gethPath).Length -eq 0) {
        Write-Error "下载失败或文件为空"
        exit 1
    }

    # 显示版本
    try {
        $version = & $gethPath version 2>&1 | Select-String "Version:" | Select-Object -First 1
        Write-Success "新客户端已下载: $version"
    } catch {
        Write-Success "新客户端已下载"
    }
}

# 下载创世文件
function Download-Genesis {
    param([string]$InstallDir)

    Write-Step "4" "下载创世配置"

    $genesisPath = Join-Path $InstallDir "genesis.json"

    # 备份旧的创世文件
    if (Test-Path $genesisPath) {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        Rename-Item $genesisPath "genesis.json.backup.$timestamp"
    }

    Write-Info "下载地址: $GENESIS_URL"

    try {
        Invoke-WebRequest -Uri $GENESIS_URL -OutFile $genesisPath -UseBasicParsing
    } catch {
        Write-Error "下载 genesis.json 失败: $_"
        exit 1
    }

    if (-not (Test-Path $genesisPath) -or (Get-Item $genesisPath).Length -eq 0) {
        Write-Error "下载 genesis.json 失败"
        exit 1
    }

    Write-Success "创世配置已下载"
}

# 重新初始化链配置（用于硬分叉）
function Initialize-Chain {
    param([string]$InstallDir)

    Write-Step "5" "重新初始化链配置（硬分叉）"

    Write-Warn "此操作仅更新链配置，现有链数据将被保留"
    Write-Host ""

    $gethPath = Join-Path $InstallDir "bin\geth.exe"
    $dataDir = Join-Path $InstallDir "data"
    $genesisPath = Join-Path $InstallDir "genesis.json"

    Write-Info "执行: geth init --datadir `"$dataDir`" `"$genesisPath`""

    & $gethPath init --datadir $dataDir $genesisPath
    if ($LASTEXITCODE -eq 0) {
        Write-Success "链配置更新成功"
    } else {
        Write-Error "链配置更新失败"
        exit 1
    }
}

# 显示完成信息
function Show-Completion {
    param([string]$InstallDir)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "        升级完成!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "升级摘要:" -ForegroundColor Blue
    Write-Host "  新版本: $GETH_VERSION"
    Write-Host "  安装目录: $InstallDir"
    Write-Host "  链数据: 已保留"
    Write-Host ""
    Write-Host "后续步骤:" -ForegroundColor Blue
    Write-Host "  1. 启动节点: $InstallDir\start-node.ps1"
    Write-Host "  2. 或后台启动: $InstallDir\start-node-bg.ps1"
    Write-Host "  3. 查看日志: Get-Content $InstallDir\logs\geth.log -Tail 50 -Wait"
    Write-Host ""
    Write-Host "重要提示:" -ForegroundColor Yellow
    Write-Host "  - 如升级失败，可从 $InstallDir\backup\ 恢复备份"
    Write-Host "  - 重启后请监控日志，确保节点正常同步"
    Write-Host ""
}

# ==================== 主流程 ====================

function Main {
    Write-Banner

    # 获取安装目录
    $installDir = Read-Host "请输入节点安装目录 [$DEFAULT_INSTALL_DIR]"
    if ([string]::IsNullOrWhiteSpace($installDir)) {
        $installDir = $DEFAULT_INSTALL_DIR
    }

    # 验证目录存在
    if (-not (Test-Path $installDir)) {
        Write-Error "目录不存在: $installDir"
        exit 1
    }

    $dataDir = Join-Path $installDir "data"
    if (-not (Test-Path $dataDir)) {
        Write-Error "未找到数据目录，这是有效的 PIJS 节点安装吗？"
        exit 1
    }

    Write-Info "升级节点: $installDir"
    Write-Host ""

    # 确认升级
    Write-Host "警告: 这将把您的节点升级到版本 $GETH_VERSION" -ForegroundColor Yellow
    Write-Host "链数据将被保留，仅更新客户端和配置。"
    Write-Host ""
    $confirm = Read-Host "确认继续升级? (y/n)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "升级已取消"
        exit 0
    }

    Stop-Node -InstallDir $installDir
    Backup-Client -InstallDir $installDir
    Download-Client -InstallDir $installDir
    Download-Genesis -InstallDir $installDir
    Initialize-Chain -InstallDir $installDir

    Show-Completion -InstallDir $installDir
}

# 运行主流程
Main
