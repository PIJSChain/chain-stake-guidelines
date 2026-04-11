#Requires -Version 5.1

# ============================================================
# PIJS 二进制更新脚本 (Windows PowerShell)
# 自动下载最新版本的二进制文件，并配置 PATH
# 不修改链数据，不更新创世配置
# ============================================================

$ErrorActionPreference = "Stop"

# ==================== 配置区域 ====================
$GitHubRepo = "PIJSChain/pijs"
$LatestReleaseApi = "https://api.github.com/repos/$GitHubRepo/releases/latest"
$DefaultInstallDir = "$env:USERPROFILE\pijs-node"
$BinaryNames = @("geth.exe", "bootnode.exe", "abigen.exe", "clef.exe", "evm.exe", "rlpdump.exe", "devp2p.exe", "ethkey.exe", "p2psim.exe")

# ==================== 工具函数 ====================

function Write-Banner {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "    PIJS 二进制更新脚本" -ForegroundColor Blue
    Write-Host "    自动更新最新 geth / bootnode 等工具" -ForegroundColor Blue
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

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[错误] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[完成] $Message" -ForegroundColor Green
}

# ==================== 核心流程 ====================

function Test-Dependencies {
    Write-Step "1" "检查运行环境"

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Error-Custom "需要 PowerShell 5.1 或更高版本"
        exit 1
    }

    if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
        Write-Error-Custom "未找到 tar 命令，请确认系统为 Windows 10/11 或已安装 tar"
        exit 1
    }

    Write-Success "运行环境检查通过"
}

function Get-LatestVersion {
    Write-Step "2" "查询最新版本"

    try {
        $release = Invoke-RestMethod -Uri $LatestReleaseApi
    } catch {
        Write-Error-Custom "查询 GitHub Release 失败: $_"
        exit 1
    }

    if (-not $release.tag_name) {
        Write-Error-Custom "无法解析最新版本号"
        exit 1
    }

    $script:LatestVersion = $release.tag_name
    $script:ReleaseDownloadBase = "https://github.com/$GitHubRepo/releases/download/$($script:LatestVersion)"
    Write-Success "最新版本: $($script:LatestVersion)"
}

function Backup-Binaries {
    param([string]$InstallDir)

    Write-Step "3" "备份现有二进制文件"

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
        Write-Success "已备份到: $backupDir"
    } else {
        Write-Info "未发现需要备份的旧二进制文件"
    }
}

function Install-LatestBinaries {
    param([string]$InstallDir)

    Write-Step "4" "下载并安装最新二进制文件"

    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Error-Custom "当前仅支持 Windows amd64 二进制包"
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
        Write-Info "下载地址: $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing

        if (-not (Test-Path $archivePath) -or (Get-Item $archivePath).Length -eq 0) {
            throw "下载失败或压缩包为空"
        }

        tar -xzf $archivePath -C $tempRoot

        $installed = $false
        foreach ($binary in $BinaryNames) {
            $sourcePath = Join-Path $tempRoot $binary
            if (Test-Path $sourcePath) {
                Move-Item $sourcePath (Join-Path $binDir $binary) -Force
                $installed = $true
                Write-Info "已更新: $binary"
            }
        }

        if (-not $installed) {
            throw "压缩包中未找到可安装的二进制文件"
        }
    } catch {
        Write-Error-Custom "安装二进制文件失败: $_"
        exit 1
    } finally {
        if (Test-Path $tempRoot) {
            Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $gethPath = Join-Path $binDir "geth.exe"
    if (Test-Path $gethPath) {
        try {
            $versionLine = (& $gethPath version 2>&1 | Select-String "Version:" | Select-Object -First 1).ToString().Trim()
            if ([string]::IsNullOrWhiteSpace($versionLine)) {
                Write-Success "二进制更新完成，Release 标签: $($script:LatestVersion)"
            } elseif ($versionLine -match [regex]::Escape($script:LatestVersion) -or $versionLine -match [regex]::Escape($script:LatestVersion.TrimStart('v'))) {
                Write-Success "二进制更新完成: $versionLine"
            } else {
                Write-Success "二进制更新完成，Release 标签: $($script:LatestVersion)，$versionLine"
            }
        } catch {
            Write-Success "二进制更新完成，Release 标签: $($script:LatestVersion)"
        }
    }
}

function Update-PathVariable {
    param([string]$InstallDir)

    Write-Step "5" "配置环境变量"

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
        Write-Info "用户 PATH 中已包含: $binDir"
    } else {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $binDir } else { "$binDir;$userPath" }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Success "已写入用户 PATH: $binDir"
    }
}

function Show-Completion {
    param([string]$InstallDir)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "        二进制更新完成!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "更新摘要:" -ForegroundColor Blue
    Write-Host "  最新版本: $($script:LatestVersion)"
    Write-Host "  安装目录: $InstallDir"
    Write-Host "  二进制目录: $(Join-Path $InstallDir 'bin')"
    Write-Host "  链数据: 未修改"
    Write-Host ""
    Write-Host "后续建议:" -ForegroundColor Blue
    Write-Host "  1. 重新打开 PowerShell 窗口使 PATH 生效"
    Write-Host "  2. 验证版本: geth version"
    Write-Host "  3. 如果本次发布涉及硬分叉，请改用 upgrade-node.ps1 完整升级"
    Write-Host ""
}

function Main {
    Write-Banner
    Write-Warn "本脚本只更新二进制文件和 PATH，不会更新 genesis.json 或重新 init。"
    Write-Host ""

    $installDir = Read-Host "请输入二进制安装目录 [$DefaultInstallDir]"
    if ([string]::IsNullOrWhiteSpace($installDir)) {
        $installDir = $DefaultInstallDir
    }

    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    Write-Info "目标目录: $installDir"

    Test-Dependencies
    Get-LatestVersion
    Backup-Binaries -InstallDir $installDir
    Install-LatestBinaries -InstallDir $installDir
    Update-PathVariable -InstallDir $installDir
    Show-Completion -InstallDir $installDir
}

Main
