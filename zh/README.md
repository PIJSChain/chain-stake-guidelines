# 共识节点部署与质押操作手册

本手册将指导您完成共识节点的部署、质押、认领和管理全过程。

## 快速导航

| 阶段 | 操作方式 | 说明 |
|------|---------|------|
| [第一步：环境准备与安装](#第一步环境准备与安装) | 命令行 | 下载文件、配置环境变量 |
| [第二步：生成密钥](#第二步生成密钥) | 命令行 | 生成 nodekey 和 BLS 密钥 |
| [第三步：启动节点](#第三步启动节点) | 命令行/脚本 | 初始化并启动节点 |
| [第四步：发起质押](#第四步发起质押) | 命令行 + Web界面 | 生成签名并在平台提交 |
| [第五步：认领节点](#第五步认领节点) | 命令行 + Web界面 | 关联钱包与节点 |
| [后续：增加质押](#后续操作增加质押) | 命令行 + Web界面 | 追加质押金额 |
| [后续：赎回质押](#赎回质押) | 命令行 + Web界面 | 到期后赎回资产 |

---

## 资源下载

| 资源 | 下载地址 |
|------|---------|
| 节点程序 | https://github.com/PIJSChain/pijs/releases/tag/v1.25.6k |
| 创世配置 | https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json |
| 引导节点 | https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/bootnodes.txt |

---

## 节点升级（已有节点）

> 如果您是新部署节点，请跳过此章节，直接查看 [开始前的准备](#开始前的准备)

当发布新版本时（特别是硬分叉升级），已有节点需要升级客户端并重新初始化链配置。

### 使用升级脚本（推荐）

我们提供了自动化升级脚本，可以自动完成客户端下载、备份和链配置更新。

#### Linux / macOS

```bash
# 下载升级脚本
curl -LO https://raw.githubusercontent.com/PIJSChain/chain-stake-guidelines/main/zh/scripts/upgrade-node.sh

# 添加执行权限
chmod +x upgrade-node.sh

# 运行脚本（按提示操作）
./upgrade-node.sh
```

#### Windows PowerShell

```powershell
# 下载升级脚本
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/PIJSChain/chain-stake-guidelines/main/zh/scripts/upgrade-node.ps1" -OutFile "upgrade-node.ps1"

# 允许脚本执行（如需要）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 运行脚本
.\upgrade-node.ps1
```

### 手动升级步骤

如果您希望手动升级：

1. **停止节点**

   ```bash
   # 停止运行中的节点
   pkill -f "geth.*--datadir.*pijs-node"
   ```

2. **备份当前客户端**

   ```bash
   cd ~/pijs-node
   mkdir -p backup
   cp bin/geth backup/geth.backup.$(date +%Y%m%d%H%M%S)
   ```

3. **下载新客户端**

   从以下地址下载对应平台的版本：
   <https://github.com/PIJSChain/pijs/releases/tag/v1.25.6k>

   ```bash
   # 以 Linux x86_64 为例
   cd ~/pijs-node/bin
   curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/geth-linux-amd64
   mv geth-linux-amd64 geth
   chmod +x geth
   ```

4. **下载新的创世配置**

   ```bash
   cd ~/pijs-node
   curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json
   ```

5. **重新初始化链配置（用于硬分叉）**

   > **重要**：此操作仅更新链配置，不会删除现有链数据

   ```bash
   cd ~/pijs-node
   ./bin/geth init --datadir data genesis.json
   ```

6. **重启节点**

   ```bash
   ./start-node.sh
   # 或后台启动
   ./start-node-bg.sh
   ```

### 验证升级

重启后，验证升级是否成功：

```bash
# 检查版本
./bin/geth version

# 连接控制台检查同步状态
geth attach ./data/geth.ipc
> eth.syncing
> eth.blockNumber
```

---

## 开始前的准备

### 系统要求

| 组件 | 最低配置 | 推荐配置 |
|------|---------|---------|
| CPU | 4核 | 8核+ |
| 内存 | 8GB | 16GB+ |
| 硬盘 | 500GB SSD | 2TB+ NVMe SSD |
| 网络 | 稳定网络连接 | 100Mbps+ |

> **重要**：节点以归档模式运行，存储需求会持续增长

### 支持的操作系统

- **Linux**: Ubuntu 20.04+, Debian 11+, CentOS 8+
- **macOS**: macOS 12+ (Monterey)
- **Windows**: Windows 10/11 64位

### 支持的架构

- **x86_64** (AMD64) - 主流服务器和桌面
- **ARM64** (aarch64) - Apple Silicon (M1/M2/M3), ARM 服务器

### 网络要求

确保以下端口可访问：

| 端口 | 协议 | 用途 |
|------|-----|------|
| 30303 | TCP/UDP | P2P 节点通信（**必须开放**） |
| 8545 | TCP | HTTP RPC（可选，按需开放） |
| 8546 | TCP | WebSocket RPC（可选，按需开放） |

---

## 第一步：环境准备与安装

### 方式一：使用一键部署脚本（推荐）

我们提供了自动化脚本，可以一键完成环境配置、密钥生成和节点启动。

#### Linux / macOS

```bash
# 下载一键部署脚本
curl -LO https://raw.githubusercontent.com/PIJSChain/chain-stake-guidelines/main/zh/scripts/setup-node-testnet.sh

# 添加执行权限
chmod +x setup-node-testnet.sh

# 运行脚本（按提示操作）
./setup-node-testnet.sh
```

#### Windows PowerShell

```powershell
# 下载一键部署脚本
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/PIJSChain/chain-stake-guidelines/main/zh/scripts/setup-node-testnet.ps1" -OutFile "setup-node-testnet.ps1"

# 允许脚本执行（首次需要）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 运行脚本
.\setup-node-testnet.ps1
```

> 使用一键脚本后，可直接跳转到 [第四步：发起质押](#第四步发起质押)

---

### 方式二：手动安装

#### 1.1 下载节点程序

访问 GitHub Release 页面下载对应平台的压缩包：

**下载地址**: <https://github.com/PIJSChain/pijs/releases/tag/v1.25.6k>

| 平台 | 文件名 |
| ---- | ------ |
| Linux x86_64 | geth-v1.25.6k-linux-amd64.tar.gz |
| Linux ARM64 | geth-v1.25.6k-linux-arm64.tar.gz |
| macOS Intel | geth-v1.25.6k-darwin-amd64.tar.gz |
| macOS Apple Silicon | geth-v1.25.6k-darwin-arm64.tar.gz |
| Windows x86_64 | geth-v1.25.6k-windows-amd64.tar.gz |

> **重要**: 压缩包内包含 `geth` 和 `bootnode` 等二进制文件，都需要添加到系统 PATH 中

#### Linux (x86_64)

```bash
# 下载
wget https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/geth-v1.25.6k-linux-amd64.tar.gz

# 解压
tar -xzf geth-v1.25.6k-linux-amd64.tar.gz

# 将 geth 和 bootnode 移动到系统路径
sudo mv geth bootnode /usr/local/bin/

# 验证安装
geth version
bootnode --help
```

#### Linux (ARM64)

```bash
wget https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/geth-v1.25.6k-linux-arm64.tar.gz
tar -xzf geth-v1.25.6k-linux-arm64.tar.gz
sudo mv geth bootnode /usr/local/bin/
geth version
```

#### macOS (Intel)

```bash
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/geth-v1.25.6k-darwin-amd64.tar.gz
tar -xzf geth-v1.25.6k-darwin-amd64.tar.gz
sudo mv geth bootnode /usr/local/bin/
geth version
```

#### macOS (Apple Silicon)

```bash
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/geth-v1.25.6k-darwin-arm64.tar.gz
tar -xzf geth-v1.25.6k-darwin-arm64.tar.gz
sudo mv geth bootnode /usr/local/bin/
geth version
```

#### Windows (x86_64)

1. 下载 `geth-v1.25.6k-windows-amd64.tar.gz`
2. 解压到目录，例如 `C:\pijs-node\bin\`
3. 将该目录添加到系统 PATH 环境变量：
   - 右键「此电脑」→「属性」→「高级系统设置」→「环境变量」
   - 在「系统变量」中找到 `Path`，点击「编辑」
   - 点击「新建」，添加 `C:\pijs-node\bin`
   - 确定保存
4. 打开**新的** PowerShell 窗口，验证安装：

```powershell
geth version
bootnode --help
```

#### 1.2 下载创世配置文件

```bash
# Linux/macOS
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json

# Windows PowerShell
Invoke-WebRequest -Uri "https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json" -OutFile "genesis.json"
```

#### 1.3 获取引导节点地址

引导节点用于连接到 PIJS 网络：

```bash
# 下载引导节点列表
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/bootnodes.txt

# 或直接使用以下地址：
enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303
enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303
enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303
```

---

## 第二步：生成密钥

### 2.1 创建工作目录

```bash
# 创建节点数据目录
mkdir -p ~/pijs-node
cd ~/pijs-node
```

### 2.2 生成 Nodekey（节点身份）

Nodekey 是节点的 P2P 身份标识，**必须固定保存**。

```bash
# 创建数据目录
mkdir -p ./data/PIJSChain

# 使用 bootnode 生成 nodekey
bootnode -genkey ./data/PIJSChain/nodekey

# 查看对应的 enode 地址
bootnode -nodekey ./data/PIJSChain/nodekey -writeaddress
```

> **重要**：`nodekey` 文件决定了您的节点身份，请妥善备份。更换 nodekey 将导致节点 enode 地址变化。

### 2.3 生成 BLS 密钥（共识签名）

BLS 密钥用于签署在线证明和质押操作。

```bash
# 生成 BLS 密钥（会提示设置密码）
geth hybrid bls generate --save ./bls-keystore.json

# 输出示例：
# [hybrid] Generating new BLS key pair...
# Public key (48 bytes): 0x8a3d6f9e2c1b4a7e...
# Enter password: ****
# Confirm password: ****
# Encrypted key saved to: ./bls-keystore.json
```

> **重要提示**
> - 密码用于加密 BLS 私钥，**务必妥善保管**
> - 密钥文件 `bls-keystore.json` 必须**安全备份**
> - 丢失密钥或密码将**无法访问质押和奖励**

### 2.4 创建密码文件

```bash
# 创建密码文件（用于自动启动）
echo "your_bls_password" > password.txt

# 设置安全权限
chmod 600 password.txt
```

### 2.5 查看 BLS 公钥

```bash
geth hybrid bls show --keyfile ./bls-keystore.json

# 输出示例：
# Enter password: ****
# BLS Public Key: 0x8a3d6f9e2c1b4a7e...
# Public Key Length: 48 bytes
```

**请记录您的 BLS 公钥**，后续质押操作会用到。

---

## 第三步：启动节点

### 3.1 初始化区块链数据

首次启动前，必须使用 genesis.json 初始化数据目录：

```bash
# 初始化（确保 genesis.json 在当前目录）
geth init --datadir ./data genesis.json

# 成功输出：
# INFO Successfully wrote genesis state
```

### 3.2 获取外网 IP

节点需要外网 IP 以便其他节点发现：

```bash
# Linux/macOS
curl -s ifconfig.me
# 或
curl -s ip.sb

# Windows PowerShell
(Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing).Content.Trim()
```

记录您的外网 IP，例如：`203.0.113.100`

### 3.3 启动节点

> **提示**：如果您使用了自动部署脚本 `setup-node-testnet.sh`（或 Windows 的 `setup-node-testnet.ps1`），启动脚本已自动生成在安装目录下，可直接运行。

#### Linux / macOS

```bash
geth \
  --datadir ./data \
  --networkid 20250521 \
  --syncmode "full" \
  --gcmode "archive" \
  --cache 4096 \
  --http \
  --http.addr "0.0.0.0" \
  --http.port 8545 \
  --http.api "eth,net,web3,hybrid" \
  --http.corsdomain "*" \
  --http.vhosts "*" \
  --ws \
  --ws.addr "0.0.0.0" \
  --ws.port 8546 \
  --ws.api "eth,net,web3,hybrid" \
  --ws.origins "*" \
  --authrpc.vhosts "*" \
  --hybrid.liveness \
  --hybrid.withdrawal "0xYourWithdrawalAddress" \
  --hybrid.blskey ./bls-keystore.json \
  --hybrid.blspassword ./password.txt \
  --nat "any" \
  --bootnodes "enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303,enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303,enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303" \
  --log.file ./logs/geth.log \
  --log.maxsize 100 \
  --log.maxbackups 10 \
  --log.compress
```

#### Windows PowerShell

```powershell
geth `
  --datadir .\data `
  --networkid 20250521 `
  --syncmode "full" `
  --gcmode "archive" `
  --cache 4096 `
  --http `
  --http.addr "0.0.0.0" `
  --http.port 8545 `
  --http.api "eth,net,web3,hybrid" `
  --http.corsdomain "*" `
  --http.vhosts "*" `
  --ws `
  --ws.addr "0.0.0.0" `
  --ws.port 8546 `
  --ws.api "eth,net,web3,hybrid" `
  --ws.origins "*" `
  --authrpc.vhosts "*" `
  --hybrid.liveness `
  --hybrid.withdrawal "0xYourWithdrawalAddress" `
  --hybrid.blskey .\bls-keystore.json `
  --hybrid.blspassword .\password.txt `
  --nat "any" `
  --bootnodes "enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303,enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303,enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303" `
  --log.file .\logs\geth.log `
  --log.maxsize 100 `
  --log.maxbackups 10 `
  --log.compress
```

**参数说明**：

| 参数 | 说明 |
|------|------|
| `--gcmode "archive"` | 归档模式，保留所有历史状态（**必需**） |
| `--hybrid.liveness` | 启用在线证明（**必需**） |
| `--hybrid.withdrawal` | 奖励接收地址 |
| `--nat "any"` | NAT 穿透模式（自动发现外网 IP） |
| `--log.file` | 日志文件路径 |
| `--log.maxsize` | 单个日志文件最大 MB |
| `--log.maxbackups` | 保留日志文件数量 |
| `--log.compress` | 压缩旧日志文件 |

#### RPC API 安全警告

> **重要**：`--http.api` 和 `--ws.api` 参数决定了哪些 API 模块对外暴露，配置不当可能导致资产损失！

| API 模块 | 安全级别 | 说明 |
|----------|---------|------|
| `eth` | 安全 | 标准以太坊 API，可对外暴露 |
| `net` | 安全 | 网络状态查询，可对外暴露 |
| `web3` | 安全 | 基础工具 API，可对外暴露 |
| `hybrid` | 安全 | 共识节点查询 API，可对外暴露 |
| `personal` | **危险** | 账户管理，**绝不可对外暴露** |
| `admin` | **危险** | 节点管理，**绝不可对外暴露** |
| `debug` | **危险** | 调试接口，**绝不可对外暴露** |
| `txpool` | 风险 | 交易池信息，不建议对外暴露 |
| `miner` | **危险** | 挖矿控制，**绝不可对外暴露** |

**安全建议**：

1. 仅暴露必要的 API：`eth,net,web3,hybrid`
2. 如果 RPC 对外暴露（`0.0.0.0`），务必配置防火墙限制访问 IP

### 3.4 验证节点状态

等待节点启动后，检查状态：

```bash
# 连接到控制台
geth attach ./data/geth.ipc

# 检查同步状态
> eth.syncing
# 返回 false 表示同步完成，返回对象表示同步中

# 检查区块高度
> eth.blockNumber

# 检查对等节点数
> net.peerCount

# 检查节点 BLS 身份
> hybrid.getNodeBLSIdentity()
```

### 3.5 后台运行（生产环境）

#### 使用 systemd（Linux 推荐）

创建服务文件 `/etc/systemd/system/geth-node.service`：

```ini
[Unit]
Description=PIJS Geth Node
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME/pijs-node
ExecStart=/usr/local/bin/geth --datadir ./data [其他参数...]
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

启动服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable geth-node
sudo systemctl start geth-node

# 查看日志
sudo journalctl -u geth-node -f
```

---

## 第四步：发起质押

节点启动并同步后，需要在 Web 平台完成质押才能开始获得奖励。

### 4.1 生成质押签名文件

在节点服务器上执行：

**Linux / macOS:**

```bash
cd ~/pijs-node

# ========== 方式一：标准模式 ==========
# 调用者地址同时作为提款地址（推荐普通用户使用）
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0xYourWalletAddress \
  --amount 10000 \
  --output deposit_data.json

# ========== 方式二：运营商模式（dPoS） ==========
# 调用者地址和提款地址分离（适用于节点运营商代理质押）
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0xCallerAddress \
  --withdrawal 0xOperatorWithdrawalAddress \
  --amount 10000 \
  --output deposit_data.json
```

**Windows PowerShell:**

```powershell
cd ~\pijs-node

# ========== 方式一：标准模式 ==========
# 调用者地址同时作为提款地址（推荐普通用户使用）
geth hybrid bls deposit `
  --keyfile .\keys\bls-keystore.json `
  --chainid 20250521 `
  --address 0xYourWalletAddress `
  --amount 10000 `
  --output deposit_data.json

# ========== 方式二：运营商模式（dPoS） ==========
# 调用者地址和提款地址分离（适用于节点运营商代理质押）
geth hybrid bls deposit `
  --keyfile .\keys\bls-keystore.json `
  --chainid 20250521 `
  --address 0xCallerAddress `
  --withdrawal 0xOperatorWithdrawalAddress `
  --amount 10000 `
  --output deposit_data.json
```

**参数说明**：

| 参数 | 说明 |
|------|------|
| `--keyfile` | BLS 密钥文件路径 |
| `--chainid` | 链 ID（测试网：20250521） |
| `--address` | 调用者钱包地址（用于支付质押金） |
| `--withdrawal` | 提款地址（可选，不填则与 address 相同） |
| `--amount` | 质押金额（PIJS） |
| `--output` | 输出文件名 |

> **模式选择**：
> - **标准模式**：个人用户自己质押，调用者即提款人
> - **运营商模式**：节点运营商代理多个用户质押，提款地址为运营商地址

**质押规则**：

| 项目 | 测试网 | 主网 |
|------|--------|------|
| 最小质押 | 2,000 PIJS | 待定 |
| 最大质押 | 100,0000 PIJS | 待定 |
| 质押期限 | 7 天 | 待定 |
| 宽限期 | 到期后 72 小时内可赎回 | 待定 |
| 自动续期 | 超过宽限期未赎回则自动续期 | 待定 |

> ⚠️ **注意**：主网质押规则待定，以上数值以官方最新公告为准，如有变动请以官方渠道发布的信息为准。

### 4.2 在 Web 平台提交质押

#### 步骤 1：连接钱包

1. 访问质押平台：`https://[STAKING_PLATFORM_URL]`
2. 点击页面右上角 **「连接钱包」** 按钮
3. 选择您的钱包（MetaMask、Trust Wallet 等）
4. 在钱包中确认授权连接

![连接钱包](./images/connect-wallet.png)

#### 步骤 2：进入质押页面

根据您的情况选择对应入口：

| 场景 | 入口方式 |
|------|----------|
| **首次质押（普通用户）** | 通过顶部导航进入 **「质押」** 页面 |
| **首次质押（成为运营商）** | 点击首页 **「成为运营商」** 轮播图 Banner（可选） |
| **已有节点，追加质押** | 进入 **「我的节点」** → 选择节点 → **「增加存款」** |
| **认领已质押节点** | 进入 **「节点快捷管理」** |

> **运营商说明**：
> - **普通用户**：单个钱包地址只能管理 **1 个** 节点
> - **运营商**：单个钱包地址可管理 **多个** 节点
>
> 如果您只需要运行一个节点，无需注册为运营商。

**首次质押流程**：

1. 进入质押页面后，显示 **「首次质押成为验证者」** 界面
2. 在此页面上传 `deposit_data.json` 文件

![成为验证者](./images/become-validator.png)

#### 步骤 3：上传质押文件

在质押页面：

1. 点击 **「上传 deposit_data.json」** 区域，或将文件拖拽到此处
2. 选择刚才在服务器上生成的 `deposit_data.json` 文件
3. 系统会自动解析并显示质押信息：
   - BLS 公钥
   - 质押金额
   - 提款地址

![上传质押文件](./images/upload-deposit.png)

#### 步骤 4：选择便捷管理（推荐）

勾选 **「自动设置便捷管理」** 选项：

- **勾选**：当前钱包地址自动关联到此节点，无需后续认领
- **不勾选**：需要手动完成节点认领步骤

> 建议勾选此选项，简化后续操作流程

#### 步骤 5：确认并提交

1. 点击 **「提交」** 按钮
2. 钱包弹出交易确认窗口，检查：
   - 交易金额（质押金额 + Gas 费）
   - 接收地址（质押合约地址）
3. 在钱包中点击 **「确认」**
4. 等待交易上链（通常 10-30 秒）

![确认交易](./images/confirm-tx.png)

#### 步骤 6：查看质押结果

交易确认后：

1. 页面自动刷新，显示 **「我的节点」** 列表
2. 查看节点信息：
   - **提款地址**：您的奖励接收地址
   - **质押数量**：已质押的 PIJS 数量
   - **节点状态**：在线/离线
   - **获得收益**：累计奖励金额

![节点列表](./images/node-list.png)

---

## 第五步：认领节点

> 如果在质押时勾选了「自动设置便捷管理」，可跳过此步骤

认领节点是将您的钱包地址与节点关联，以便在 Web 平台管理节点。

### 5.1 获取 Challenge 值

1. 在 **「我的节点」** 页面，点击您的节点进入详情
2. 点击 **「设置便捷管理」** 或 **「认领节点」** 按钮
3. 系统显示一个 **Challenge 值**（32 字节十六进制字符串）
4. 点击 Challenge 值旁边的 **「复制」** 按钮

![获取Challenge](./images/get-challenge.png)

### 5.2 生成认领签名

回到服务器，使用 BLS 密钥对 Challenge 签名：

**Linux / macOS:**

```bash
cd ~/pijs-node

# 使用从 Web 界面复制的 Challenge 值
geth hybrid bls sign \
  --keyfile ./keys/bls-keystore.json \
  --message 0x1234abcd5678ef90... \
  --output easy_management_setup.json
```

**Windows PowerShell:**

```powershell
cd ~\pijs-node

# 使用从 Web 界面复制的 Challenge 值
geth hybrid bls sign `
  --keyfile .\keys\bls-keystore.json `
  --message 0x1234abcd5678ef90... `
  --output easy_management_setup.json
```

输出示例：

```text
[hybrid] BLS Signature Data
Message: 0x1234abcd5678ef90...
BLS Public Key: 0x8a3d6f9e...
Signature: 0x2b3c4d5e...
Signature data saved to: easy_management_setup.json
```

### 5.3 上传认领签名

1. 回到 Web 平台的 **「设置便捷管理」** 界面
2. 点击 **「上传签名文件」** 区域
3. 选择 `easy_management_setup.json` 文件
4. 点击 **「提交」** 按钮

![上传认领签名](./images/upload-claim.png)

### 5.4 验证认领成功

认领成功后：

- 节点显示在 **「我的节点」** 列表中
- 可以查看详细的质押订单
- 可以进行增加质押、赎回等操作

---

## 后续操作：增加质押

如需增加已有节点的质押金额：

### 6.1 生成新的质押签名

**Linux / macOS:**

```bash
cd ~/pijs-node

# 每次质押都需要生成新的签名文件
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0xYourWalletAddress \
  --amount 5000 \
  --output deposit_additional.json
```

**Windows PowerShell:**

```powershell
cd ~\pijs-node

# 每次质押都需要生成新的签名文件
geth hybrid bls deposit `
  --keyfile .\keys\bls-keystore.json `
  --chainid 20250521 `
  --address 0xYourWalletAddress `
  --amount 5000 `
  --output deposit_additional.json
```

> **注意**：不能重复使用同一签名文件，每次都需要重新生成

### 6.2 在 Web 平台提交

1. 进入 **「我的节点」** 页面
2. 点击要增加质押的节点，进入 **「仪表板」** 视图
3. 点击 **「增加存款」** 链接（或「我要增加存款」按钮）
4. 在跳转的页面中：
   - 上传新生成的 `deposit_additional.json` 文件
   - 点击 **「提交」**
5. 在钱包中确认交易

![增加质押](./images/add-deposit.png)

### 6.3 查看质押订单

增加质押后，会生成新的质押订单：

1. 在节点 **「仪表板」** 页面
2. 查看 **「质押订单」** 列表，切换标签：
   - **存款中/可赎回**：活跃订单
   - **已赎回**：历史订单
3. 每个订单显示：
   - 存款数量
   - 存入时间
   - 可赎时间
   - 状态（存款中 / 可赎回）

![质押订单](./images/stake-orders.png)

---

## 赎回质押

当质押订单到期后，可在宽限期内赎回资产。

### 7.1 赎回时间线

```
质押开始 ────── 质押期限 ──────> 到期 ────── 72小时宽限期 ──────> 自动续期
         获得奖励期间           可赎回窗口              无法赎回，重新开始下一周期
```

> 测试网质押期限为 7 天，主网质押期限待定。

### 7.2 检查可赎回订单

1. 进入节点 **「仪表板」** 页面
2. 在 **「质押订单」** 列表中
3. 状态为 **「可赎回」** 的订单可以赎回

### 7.3 生成赎回签名

**Linux / macOS:**

```bash
cd ~/pijs-node

geth hybrid bls redeem \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --orderid 1 \
  --withdrawal 0xYourWithdrawalAddress \
  --recipient 0xYourRecipientAddress \
  --output redeem_data.json
```

**Windows PowerShell:**

```powershell
cd ~\pijs-node

geth hybrid bls redeem `
  --keyfile .\keys\bls-keystore.json `
  --chainid 20250521 `
  --orderid 1 `
  --withdrawal 0xYourWithdrawalAddress `
  --recipient 0xYourRecipientAddress `
  --output redeem_data.json
```

**参数说明：**

- `--orderid`：订单 ID（从 Web 界面查看）
- `--withdrawal`：提款地址（必须与质押时一致）
- `--recipient`：资金接收地址（可以是任意地址）

### 7.4 在 Web 平台赎回

1. 在节点 **「仪表板」** 页面
2. 展开 **「质押赎回」** 折叠区域
3. 点击 **「上传 redeem_data.json」** 区域
4. 选择刚才生成的赎回签名文件
5. 点击 **「提交」** 按钮
6. 在钱包中确认交易

![赎回质押](./images/redeem.png)

### 7.5 验证赎回成功

赎回成功后：

- 订单状态变为 **「已赎回」**
- 资金已转入指定的 `recipient` 地址
- 该订单的质押量从节点总质押中扣除

---

## 常见问题

### 什么是验证者（节点）？

验证者是存在于信标链上的虚拟实体，以余额、公钥和其他属性表示，它参与了 PIJSChain 网络达成共识的过程。

### 什么是验证者客户端？

验证者客户端是一种软件，它通过保存并使用验证者的私钥来代表验证者执行操作，以便认证链状态。

### 什么是节点运营者？

节点运营商是确保客户端软件正常运行并按需维护硬件的人。

### 要成为验证者，我需要质押多少 PIJS？

| 网络   | 最小质押   | 最大质押     |
|--------|------------|--------------|
| 测试网 | 2,000 PIJS | 100,0000 PIJS |
| 主网   | 待定       | 待定         |

超过最大质押额度的部分不参与奖励计算。

> ⚠️ 主网质押规则待定，以官方最新公告为准。

### 为什么要质押 PIJS？

作为验证者，您需要有相关资金才能因不诚实行为而受到惩罚。换句话说，为了让您保持诚实，您的行为需要产生财务后果。

### 验证者奖励是什么？

验证者根据质押网络权重获得 PIJS 代币奖励。

### 我在什么时候可以提取质押的 PIJS？

质押到期后可在 **72 小时**内解锁。72 小时内未解锁将自动进入下个周期。测试网质押期限为 7 天，主网质押期限待定。

### PIJSChain 质押奖励如何结算？

PIJSChain 质押结算为**日结**，前一天网络共识产生的奖励会在第二天陆续发放至对应提款地址。

### 为什么年化利率会变化？

收益率与你的质押量和网络共识权重有关系。

### 如果我离线了会被罚没吗？

**不会**。当你离线或网络无法验证你在线时，表示你无法参与 PIJSChain 网络共识，质押奖励会停止，直到可以重新参与共识。**不会扣除本金**。

### 什么是提款地址？

用于接收你质押奖励的地址。

### 我可以修改提款地址吗？

**不可以**。提款地址在首次质押时确定，无法修改。解锁质押时必须使用相同的提款地址签名。

### 如何提取我的质押奖励？

无需手动提取，奖励由网络根据质押数量和共识权重**自动发送至提款地址**。

### 如何解锁我质押的 PIJS？

使用你的 BLS 私钥对系统随机 Challenge 值签名，提交签名至网络，验证通过后你将收到你质押的 PIJS。

### 什么是节点认领（便捷管理）？

节点认领（Claim Node）通过 BLS 签名证明你拥有该验证者的私钥，从而将验证者关联到你的钱包地址。关联后，你可以：

- ✅ 在 Web 界面查看该验证者的详细信息
- ✅ 管理验证者的质押订单
- ✅ 进行增加质押、赎回等操作

### 如果我的 BLS 密钥忘记或丢失会发生什么？

如果您丢失了签名密钥，您的验证者将**无法继续质押和提取资金**。请务必妥善备份密钥文件和密码。

### 如何防范网络钓鱼行为？

1. **注意仔细检查 URL** - 是否存在拼写错误？
2. **交叉检查合约地址** - 对照其他官方网站核实保证金合约地址
3. **签字前核实合同地址** - 在钱包中仔细核实
4. **检查完整地址** - 不要只检查其中的一部分，可能只有几个字节不同

---

## 快速命令参考

### BLS 密钥管理

```bash
# 生成密钥
geth hybrid bls generate --save ./bls-keystore.json

# 查看公钥
geth hybrid bls show --keyfile ./bls-keystore.json

# 导入已有私钥
geth hybrid bls import --privkey 0x... --save ./bls-keystore.json
```

### 签名生成

**Linux / macOS:**

```bash
# 质押签名（标准模式）
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0x... \
  --amount 10000 \
  --output deposit_data.json

# 质押签名（运营商模式 - 指定独立提款地址）
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0x... \
  --withdrawal 0x... \
  --amount 10000 \
  --output deposit_data.json

# 认领签名
geth hybrid bls sign \
  --keyfile ./keys/bls-keystore.json \
  --message 0x... \
  --output easy_management_setup.json

# 赎回签名
geth hybrid bls redeem \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --orderid 1 \
  --withdrawal 0x... \
  --recipient 0x... \
  --output redeem_data.json
```

**Windows PowerShell:**

```powershell
# 质押签名（标准模式）
geth hybrid bls deposit `
  --keyfile .\keys\bls-keystore.json `
  --chainid 20250521 `
  --address 0x... `
  --amount 10000 `
  --output deposit_data.json

# 质押签名（运营商模式 - 指定独立提款地址）
geth hybrid bls deposit `
  --keyfile .\keys\bls-keystore.json `
  --chainid 20250521 `
  --address 0x... `
  --withdrawal 0x... `
  --amount 10000 `
  --output deposit_data.json

# 认领签名
geth hybrid bls sign `
  --keyfile .\keys\bls-keystore.json `
  --message 0x... `
  --output easy_management_setup.json

# 赎回签名
geth hybrid bls redeem `
  --keyfile .\keys\bls-keystore.json `
  --chainid 20250521 `
  --orderid 1 `
  --withdrawal 0x... `
  --recipient 0x... `
  --output redeem_data.json
```

### 节点操作

```bash
# 连接控制台
geth attach ./data/geth.ipc

# 检查同步状态
> eth.syncing

# 检查区块高度
> eth.blockNumber

# 检查对等节点
> net.peerCount

# 检查节点身份
> hybrid.getNodeBLSIdentity()

# 检查在线状态
> hybrid.getLivenessStatus()
```

---

## 获取帮助

- 支持邮箱：[support@pijschain.com]

