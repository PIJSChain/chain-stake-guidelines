# ============================================================
# PIJS 共识节点升级脚本 (Windows PowerShell)
# 用于硬分叉升级 - 仅更新客户端和链配置
# 不会删除现有链数据
# ============================================================

$ErrorActionPreference = "Stop"

# ==================== 配置区域 ====================
$GITHUB_RELEASE = "https://github.com/PIJSChain/pijs/releases/download/v1.26.0"
$GETH_VERSION = "v1.26.0"
$GENESIS_URL = "https://github.com/PIJSChain/pijs/releases/download/v1.26.0/genesis.json"

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

    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    $platform = "windows-$arch"
    $gethTar = "geth-$GETH_VERSION-$platform.tar.gz"
    $downloadUrl = "$GITHUB_RELEASE/$gethTar"

    Write-Info "下载地址: $downloadUrl"

    $downloadPath = Join-Path $InstallDir $gethTar

    # 下载压缩包
    if (Test-Path $downloadPath) {
        Remove-Item $downloadPath -Force
    }

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
    } catch {
        Write-Error "下载失败: $_"
        exit 1
    }

    # 验证下载
    if (-not (Test-Path $downloadPath) -or (Get-Item $downloadPath).Length -eq 0) {
        Write-Error "下载失败或文件为空"
        exit 1
    }

    # 解压
    Write-Info "解压文件..."
    Set-Location $InstallDir
    tar -xzf $gethTar

    # 创建 bin 目录
    $binDir = Join-Path $InstallDir "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    # 移动所有二进制文件到 bin 目录
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

    # 清理压缩包
    Remove-Item $downloadPath -Force

    # 显示版本
    $gethPath = Join-Path $binDir "geth.exe"
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

# 交互式选择 NAT 模式（与 setup 一致）
function Choose-NatMode {
    Write-Host ""
    Write-Host "请选择您的网络环境:"
    Write-Host ""
    Write-Host "  1) 固定公网IP - 服务器有固定的公网IP地址"
    Write-Host "  2) NAT环境   - 位于路由器/NAT网关后面（家庭网络、部分云服务器）"
    Write-Host "  3) 自动检测  - 每次启动时自动检测公网IP（推荐）"
    Write-Host ""

    $done = $false
    while (-not $done) {
        $choice = Read-Host "请选择 [1-3] (默认: 3)"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "3" }

        switch ($choice) {
            "1" {
                Write-Host ""
                Write-Info "正在检测您的公网IP..."
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
                    Write-Host "检测到IP: $detectedIp"
                    $confirm = Read-Host "使用此IP? (y/n, 或输入其他IP)"
                    if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -match "^[Yy]$") {
                        $script:NAT_MODE = "extip"
                        $script:PUBLIC_IP = $detectedIp
                        $done = $true
                    } elseif ($confirm -match "^\d+\.\d+\.\d+\.\d+$") {
                        $script:NAT_MODE = "extip"
                        $script:PUBLIC_IP = $confirm
                        $done = $true
                    } else {
                        Write-Host "输入无效，请重试"
                    }
                } else {
                    $manualIp = Read-Host "无法检测公网IP，请手动输入您的公网IP"
                    if ($manualIp -match "^\d+\.\d+\.\d+\.\d+$") {
                        $script:NAT_MODE = "extip"
                        $script:PUBLIC_IP = $manualIp
                        $done = $true
                    } else {
                        Write-Error "IP地址格式无效"
                    }
                }
            }
            "2" {
                $script:NAT_MODE = "any"
                $script:PUBLIC_IP = ""
                Write-Info "已选择NAT模式，将使用UPnP/NAT-PMP自动端口映射"
                $done = $true
            }
            "3" {
                $script:NAT_MODE = "auto"
                $script:PUBLIC_IP = ""
                Write-Info "自动检测模式，每次启动时检测公网IP"
                $done = $true
            }
            default {
                Write-Host "选择无效，请输入 1、2 或 3"
            }
        }
    }
}

# 根据 NAT_MODE 返回 NAT 配置块（供嵌入 start-node.ps1）
function Get-NatSection {
    switch ($script:NAT_MODE) {
        "extip" {
            return @"
# 固定公网IP模式
`$NAT_CONFIG = "extip:$($script:PUBLIC_IP)"
Write-Host "NAT配置: `$NAT_CONFIG (固定公网IP)"
"@
        }
        "any" {
            return @"
# NAT环境模式 (UPnP/NAT-PMP)
`$NAT_CONFIG = "any"
Write-Host "NAT配置: `$NAT_CONFIG (自动端口映射)"
"@
        }
        default {
            return @'
# 自动检测公网IP
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

Write-Host "正在检测公网IP..."
$DETECTED_IP = Get-PublicIp
if ($DETECTED_IP) {
    $NAT_CONFIG = "extip:$DETECTED_IP"
    Write-Host "  检测到公网IP: $DETECTED_IP"
    Write-Host "  NAT配置: $NAT_CONFIG"
} else {
    $NAT_CONFIG = "any"
    Write-Host "  未检测到公网IP，回退到 NAT: any"
}
'@
        }
    }
}

# 可选：重新配置网络
function Reconfigure-Network {
    param([string]$InstallDir)

    Write-Step "6" "网络配置（可选）"

    Write-Host ""
    Write-Host "此步骤可以重新配置节点的 NAT 网络模式"
    Write-Host "仅在以下情况需要执行："
    Write-Host "  - 服务器 IP 变更"
    Write-Host "  - 从家用网络迁移到云主机（反之亦然）"
    Write-Host "  - 升级前 NAT 配置不正确（如 peer 数长期为 0）"
    Write-Host ""

    $reset = Read-Host "是否重新配置网络？(y/N)"
    if ($reset -notmatch "^[Yy]$") {
        Write-Info "跳过网络配置（保持现有设置）"
        return
    }

    $startScript = Join-Path $InstallDir "start-node.ps1"
    if (-not (Test-Path $startScript)) {
        Write-Error "未找到 $startScript"
        Write-Error "建议重新运行 setup-node-testnet.ps1 重新部署"
        return
    }

    # 定位 NAT 配置块的起止行
    $content = Get-Content $startScript
    $startIdx = -1
    $endIdx = -1
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match "^# ==================== NAT 配置 ====================$") { $startIdx = $i }
        if ($content[$i] -match "^# ==================== 启动节点 ====================$") { $endIdx = $i; break }
    }

    if ($startIdx -lt 0 -or $endIdx -lt 0 -or $endIdx -le $startIdx) {
        Write-Error "start-node.ps1 格式不兼容（可能是旧版本脚本生成的）"
        Write-Error "建议重新运行 setup-node-testnet.ps1 重新部署"
        return
    }

    # 询问 NAT 模式
    Choose-NatMode

    # 备份现有 start-node.ps1
    $backupDir = Join-Path $InstallDir "backup"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupFile = Join-Path $backupDir "start-node.ps1.$timestamp"
    Copy-Item $startScript $backupFile
    Write-Info "已备份原 start-node.ps1 至: $backupFile"

    # 生成新 NAT 配置块（按行切分）
    $natSection = Get-NatSection
    $natLines = $natSection -split "`r?`n"

    # 重建: [0..startIdx] + 新NAT + [endIdx..end]
    $newContent = @()
    $newContent += $content[0..$startIdx]
    $newContent += $natLines
    $newContent += $content[$endIdx..($content.Count - 1)]
    Set-Content -Path $startScript -Value $newContent

    Write-Success "网络配置已更新为: $($script:NAT_MODE)"
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
    Write-Host "网络连接诊断:" -ForegroundColor Blue
    Write-Host "  如果启动后 peerCount 为 0，可使用 devp2p 工具检测引导节点连通性:"
    Write-Host "  devp2p discv4 ping <enode-url>" -ForegroundColor Cyan
    Write-Host "  示例: devp2p discv4 ping enode://6f05...fb@54.169.152.20:30303"
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
    Reconfigure-Network -InstallDir $installDir

    Show-Completion -InstallDir $installDir
}

# 运行主流程
Main
