# Consensus Node Deployment and Staking Guide

This guide covers the complete process of deploying a PIJS consensus node, including staking, claiming, and management operations.

## Quick Navigation

| Step | Method | Description |
|------|--------|-------------|
| [Step 1: Environment Setup](#step-1-environment-setup-and-installation) | CLI | Download files, configure environment |
| [Step 2: Generate Keys](#step-2-generate-keys) | CLI | Generate nodekey and BLS keys |
| [Step 3: Start Node](#step-3-start-the-node) | CLI/Script | Initialize and start node |
| [Step 4: Initiate Staking](#step-4-initiate-staking) | CLI + Web | Generate signature and submit on platform |
| [Step 5: Claim Node](#step-5-claim-node) | CLI + Web | Link wallet to node |
| [Additional: Add Stake](#additional-add-more-stake) | CLI + Web | Add more stake amount |
| [Additional: Redeem Stake](#redeem-stake) | CLI + Web | Redeem assets after maturity |

---

## Resource Downloads

| Resource | Download URL |
|----------|--------------|
| Node Binary | https://github.com/PIJSChain/pijs/releases/tag/v1.25.6h |
| Genesis Config | https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/genesis.json |
| Bootstrap Nodes | https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/bootnodes.txt |

---

## Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| Memory | 8GB | 16GB+ |
| Storage | 500GB SSD | 2TB+ NVMe SSD |
| Network | Stable connection | 100Mbps+ |

> **Important**: Node runs in archive mode, storage requirements will grow continuously

### Supported Operating Systems

- **Linux**: Ubuntu 20.04+, Debian 11+, CentOS 8+
- **macOS**: macOS 12+ (Monterey)
- **Windows**: Windows 10/11 64-bit

### Supported Architectures

- **x86_64** (AMD64) - Standard servers and desktops
- **ARM64** (aarch64) - Apple Silicon (M1/M2/M3), ARM servers

### Network Requirements

Ensure the following ports are accessible:

| Port | Protocol | Purpose |
|------|----------|---------|
| 30303 | TCP/UDP | P2P node communication (**required**) |
| 8545 | TCP | HTTP RPC (optional) |
| 8546 | TCP | WebSocket RPC (optional) |

---

## Step 1: Environment Setup and Installation

### Option 1: One-Click Deployment Script (Recommended)

We provide automated scripts for environment configuration, key generation, and node startup.

#### Linux / macOS

```bash
# Download deployment script
curl -LO https://[DOWNLOAD_HOST]/deploy/setup-node-testnet.sh

# Add execute permission
chmod +x setup-node-testnet.sh

# Run script (follow prompts)
./setup-node-testnet.sh
```

#### Windows PowerShell

```powershell
# Download deployment script
Invoke-WebRequest -Uri "https://[DOWNLOAD_HOST]/deploy/setup-node-testnet.ps1" -OutFile "setup-node-testnet.ps1"

# Allow script execution (first time only)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run script
.\setup-node-testnet.ps1
```

> After using the one-click script, skip to [Step 4: Initiate Staking](#step-4-initiate-staking)

---

### Option 2: Manual Installation

#### 1.1 Download Node Binary

Visit the GitHub Release page to download the archive for your platform:

**Download URL**: <https://github.com/PIJSChain/pijs/releases/tag/v1.25.6h>

| Platform | Filename |
|----------|----------|
| Linux x86_64 | geth-v1.25.6h-linux-amd64.tar.gz |
| Linux ARM64 | geth-v1.25.6h-linux-arm64.tar.gz |
| macOS Intel | geth-v1.25.6h-darwin-amd64.tar.gz |
| macOS Apple Silicon | geth-v1.25.6h-darwin-arm64.tar.gz |
| Windows x86_64 | geth-v1.25.6h-windows-amd64.tar.gz |

> **Important**: The archive contains `geth` and `bootnode` binaries, both need to be added to system PATH

#### Linux (x86_64)

```bash
# Download
wget https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/geth-v1.25.6h-linux-amd64.tar.gz

# Extract
tar -xzf geth-v1.25.6h-linux-amd64.tar.gz

# Move geth and bootnode to system path
sudo mv geth bootnode /usr/local/bin/

# Verify installation
geth version
bootnode --help
```

#### Linux (ARM64)

```bash
wget https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/geth-v1.25.6h-linux-arm64.tar.gz
tar -xzf geth-v1.25.6h-linux-arm64.tar.gz
sudo mv geth bootnode /usr/local/bin/
geth version
```

#### macOS (Intel)

```bash
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/geth-v1.25.6h-darwin-amd64.tar.gz
tar -xzf geth-v1.25.6h-darwin-amd64.tar.gz
sudo mv geth bootnode /usr/local/bin/
geth version
```

#### macOS (Apple Silicon)

```bash
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/geth-v1.25.6h-darwin-arm64.tar.gz
tar -xzf geth-v1.25.6h-darwin-arm64.tar.gz
sudo mv geth bootnode /usr/local/bin/
geth version
```

#### Windows (x86_64)

1. Download `geth-v1.25.6h-windows-amd64.tar.gz`
2. Extract to a directory, e.g., `C:\pijs-node\bin\`
3. Add the directory to system PATH:
   - Right-click "This PC" → "Properties" → "Advanced system settings" → "Environment Variables"
   - Find `Path` in "System variables", click "Edit"
   - Click "New", add `C:\pijs-node\bin`
   - Click OK to save
4. Open a **new** PowerShell window to verify:

```powershell
geth version
bootnode --help
```

#### 1.2 Download Genesis Configuration

```bash
# Linux/macOS
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/genesis.json

# Windows PowerShell
Invoke-WebRequest -Uri "https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/genesis.json" -OutFile "genesis.json"
```

#### 1.3 Get Bootstrap Node Addresses

Bootstrap nodes are used to connect to the PIJS network:

```bash
# Download bootstrap node list
curl -LO https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/bootnodes.txt

# Or use the following addresses directly:
enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303
enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303
enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303
```

---

## Step 2: Generate Keys

### 2.1 Create Working Directory

```bash
# Create node data directory
mkdir -p ~/pijs-node
cd ~/pijs-node
```

### 2.2 Generate Nodekey (Node Identity)

Nodekey is the P2P identity of your node, **must be preserved**.

```bash
# Create data directory
mkdir -p ./data/PIJSChain

# Generate nodekey using bootnode
bootnode -genkey ./data/PIJSChain/nodekey

# View corresponding enode address
bootnode -nodekey ./data/PIJSChain/nodekey -writeaddress
```

> **Important**: The `nodekey` file determines your node identity. Back it up securely. Changing nodekey will change your node's enode address.

### 2.3 Generate BLS Key (Consensus Signing)

BLS key is used for signing liveness proofs and staking operations.

```bash
# Generate BLS key (will prompt for password)
geth hybrid bls generate --save ./bls-keystore.json

# Example output:
# [hybrid] Generating new BLS key pair...
# Public key (48 bytes): 0x8a3d6f9e2c1b4a7e...
# Enter password: ****
# Confirm password: ****
# Encrypted key saved to: ./bls-keystore.json
```

> **Important Notes**
> - Password encrypts BLS private key, **keep it safe**
> - Key file `bls-keystore.json` must be **securely backed up**
> - Losing key or password means **loss of access to stake and rewards**

### 2.4 Create Password File

```bash
# Create password file (for auto-start)
echo "your_bls_password" > password.txt

# Set secure permissions
chmod 600 password.txt
```

### 2.5 View BLS Public Key

```bash
geth hybrid bls show --keyfile ./bls-keystore.json

# Example output:
# Enter password: ****
# BLS Public Key: 0x8a3d6f9e2c1b4a7e...
# Public Key Length: 48 bytes
```

**Record your BLS public key** for later staking operations.

---

## Step 3: Start the Node

### 3.1 Initialize Blockchain Data

Before first start, initialize data directory with genesis.json:

```bash
# Initialize (ensure genesis.json is in current directory)
geth init --datadir ./data genesis.json

# Success output:
# INFO Successfully wrote genesis state
```

### 3.2 Get External IP

Node needs external IP for peer discovery:

```bash
# Linux/macOS
curl -s ifconfig.me
# or
curl -s ip.sb

# Windows PowerShell
(Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing).Content.Trim()
```

Record your external IP, e.g., `203.0.113.100`

### 3.3 Start Node

> **Tip**: If you used the automated deployment script `setup-node-testnet.sh`, the start script `start-node.sh` is already generated in the installation directory and can be run directly.

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
  --nat "extip:203.0.113.100" \
  --bootnodes "enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303,enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303,enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303" \
  --log.file ./logs/geth.log \
  --log.maxsize 100 \
  --log.maxbackups 10 \
  --log.compress
```

**Parameter Description**:

| Parameter | Description |
|-----------|-------------|
| `--gcmode "archive"` | Archive mode, keeps all historical state (**required**) |
| `--hybrid.liveness` | Enable liveness proofs (**required**) |
| `--hybrid.withdrawal` | Reward receiving address |
| `--nat "extip:..."` | External IP (for P2P discovery) |
| `--log.file` | Log file path |
| `--log.maxsize` | Max size per log file (MB) |
| `--log.maxbackups` | Number of log files to keep |
| `--log.compress` | Compress old log files |

#### RPC API Security Warning

> **Important**: `--http.api` and `--ws.api` parameters determine which API modules are exposed. Improper configuration may result in asset loss!

| API Module | Security Level | Description |
|------------|---------------|-------------|
| `eth` | Safe | Standard Ethereum API, can be exposed |
| `net` | Safe | Network status queries, can be exposed |
| `web3` | Safe | Basic utility API, can be exposed |
| `hybrid` | Safe | Consensus node query API, can be exposed |
| `personal` | **Dangerous** | Account management, **never expose** |
| `admin` | **Dangerous** | Node management, **never expose** |
| `debug` | **Dangerous** | Debug interface, **never expose** |
| `txpool` | Risky | Transaction pool info, not recommended |
| `miner` | **Dangerous** | Mining control, **never expose** |

**Security Recommendations**:

1. Only expose necessary APIs: `eth,net,web3,hybrid`
2. If RPC is externally exposed (`0.0.0.0`), configure firewall to restrict access IPs

### 3.4 Verify Node Status

After node starts, check status:

```bash
# Connect to console
geth attach ./data/geth.ipc

# Check sync status
> eth.syncing
# Returns false when synced, returns object when syncing

# Check block height
> eth.blockNumber

# Check peer count
> net.peerCount

# Check node BLS identity
> hybrid.getNodeBLSIdentity()
```

### 3.5 Background Running (Production)

#### Using systemd (Linux Recommended)

Create service file `/etc/systemd/system/geth-node.service`:

```ini
[Unit]
Description=PIJS Geth Node
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME/pijs-node
ExecStart=/usr/local/bin/geth --datadir ./data [other parameters...]
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Start service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable geth-node
sudo systemctl start geth-node

# View logs
sudo journalctl -u geth-node -f
```

---

## Step 4: Initiate Staking

After node is started and synced, complete staking on Web platform to start earning rewards.

### 4.1 Generate Staking Signature File

Execute on node server:

```bash
cd ~/pijs-node

# ========== Method 1: Standard Mode ==========
# Caller address is also used as withdrawal address (recommended for regular users)
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0xYourWalletAddress \
  --amount 10000 \
  --output deposit_data.json

# ========== Method 2: Operator Mode (dPoS) ==========
# Caller address and withdrawal address are separate (for node operators managing delegated stakes)
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0xCallerAddress \
  --withdrawal 0xOperatorWithdrawalAddress \
  --amount 10000 \
  --output deposit_data.json
```

**Parameter Description**:

| Parameter | Description |
|-----------|-------------|
| `--keyfile` | BLS key file path |
| `--chainid` | Chain ID (Testnet: 20250521) |
| `--address` | Caller wallet address (for paying stake) |
| `--withdrawal` | Withdrawal address (optional, defaults to same as address) |
| `--amount` | Stake amount (PIJS) |
| `--output` | Output filename |

> **Mode Selection**:
> - **Standard Mode**: Individual users staking for themselves, caller is also the withdrawal recipient
> - **Operator Mode**: Node operators managing delegated stakes from multiple users, withdrawal address is the operator's address

**Staking Rules**:

| Item | Testnet | Mainnet |
|------|---------|---------|
| Minimum Stake | 2,000 PIJS | TBD |
| Maximum Stake | 100,000 PIJS | TBD |
| Stake Period | 7 days | TBD |
| Grace Period | 72 hours after maturity | TBD |
| Auto-renewal | Auto-renews if not redeemed | TBD |

> ⚠️ **Note**: Mainnet staking rules are TBD. The above values are subject to official announcements. Please refer to official channels for the latest information.

### 4.2 Submit Staking on Web Platform

#### Step 1: Connect Wallet

1. Visit staking platform: `https://[STAKING_PLATFORM_URL]`
2. Click **"Connect Wallet"** button at top right
3. Select your wallet (MetaMask, Trust Wallet, etc.)
4. Confirm authorization in wallet

![Connect Wallet](./images/connect-wallet.png)

#### Step 2: Enter Staking Page

Choose entry point based on your situation:

| Scenario | Entry Method |
|----------|--------------|
| **First stake (Regular user)** | Navigate to **"Staking"** page via top menu |
| **First stake (Become operator)** | Click **"Become Operator"** banner on homepage (optional) |
| **Existing node, add stake** | Go to **"My Nodes"** → Select node → **"Add Deposit"** |
| **Claim staked node** | Go to **"Node Quick Management"** |

> **Operator Note**:
> - **Regular user**: Single wallet address can manage **1** node only
> - **Operator**: Single wallet address can manage **multiple** nodes
>
> If you only need to run one node, no need to register as operator.

**First Staking Flow**:

1. Enter staking page, shows **"First Stake to Become Validator"** interface
2. Upload `deposit_data.json` file on this page

![Become Validator](./images/become-validator.png)

#### Step 3: Upload Staking File

On staking page:

1. Click **"Upload deposit_data.json"** area, or drag file here
2. Select the `deposit_data.json` file generated on server
3. System auto-parses and displays staking info:
   - BLS Public Key
   - Stake Amount
   - Withdrawal Address

![Upload Deposit File](./images/upload-deposit.png)

#### Step 4: Select Easy Management (Recommended)

Check **"Auto-setup Easy Management"** option:

- **Checked**: Current wallet address auto-links to this node, no claiming needed
- **Unchecked**: Need to manually complete node claiming step

> Recommend checking this option to simplify subsequent operations

#### Step 5: Confirm and Submit

1. Click **"Submit"** button
2. Wallet pops up transaction confirmation, check:
   - Transaction amount (stake amount + Gas fee)
   - Recipient address (staking contract address)
3. Click **"Confirm"** in wallet
4. Wait for transaction confirmation (usually 10-30 seconds)

![Confirm Transaction](./images/confirm-tx.png)

#### Step 6: View Staking Result

After transaction confirms:

1. Page auto-refreshes, shows **"My Nodes"** list
2. View node info:
   - **Withdrawal Address**: Your reward receiving address
   - **Stake Amount**: Staked PIJS amount
   - **Node Status**: Online/Offline
   - **Earned Rewards**: Cumulative reward amount

![Node List](./images/node-list.png)

---

## Step 5: Claim Node

> Skip this step if you checked "Auto-setup Easy Management" during staking

Claiming node links your wallet address to the node for Web platform management.

### 5.1 Get Challenge Value

1. On **"My Nodes"** page, click your node to enter details
2. Click **"Setup Easy Management"** or **"Claim Node"** button
3. System displays a **Challenge value** (32-byte hex string)
4. Click **"Copy"** button next to Challenge value

![Get Challenge](./images/get-challenge.png)

### 5.2 Generate Claim Signature

Return to server, sign Challenge with BLS key:

```bash
cd ~/pijs-node

# Use Challenge value copied from Web interface
geth hybrid bls sign \
  --keyfile ./keys/bls-keystore.json \
  --message 0x1234abcd5678ef90... \
  --output easy_management_setup.json

# Output:
# [hybrid] BLS Signature Data
# Message: 0x1234abcd5678ef90...
# BLS Public Key: 0x8a3d6f9e...
# Signature: 0x2b3c4d5e...
# Signature data saved to: easy_management_setup.json
```

### 5.3 Upload Claim Signature

1. Return to Web platform's **"Setup Easy Management"** interface
2. Click **"Upload Signature File"** area
3. Select `easy_management_setup.json` file
4. Click **"Submit"** button

![Upload Claim Signature](./images/upload-claim.png)

### 5.4 Verify Claim Success

After successful claim:

- Node appears in **"My Nodes"** list
- Can view detailed staking orders
- Can perform add stake, redeem operations

---

## Additional: Add More Stake

To add more stake to existing node:

### 6.1 Generate New Staking Signature

```bash
cd ~/pijs-node

# Each stake requires new signature file
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0xYourWalletAddress \
  --amount 5000 \
  --output deposit_additional.json
```

> **Note**: Cannot reuse same signature file, must regenerate each time

### 6.2 Submit on Web Platform

1. Go to **"My Nodes"** page
2. Click the node to add stake, enter **"Dashboard"** view
3. Click **"Add Deposit"** link (or "I want to add deposit" button)
4. On the redirected page:
   - Upload newly generated `deposit_additional.json` file
   - Click **"Submit"**
5. Confirm transaction in wallet

![Add Deposit](./images/add-deposit.png)

### 6.3 View Staking Orders

After adding stake, new staking order is created:

1. On node **"Dashboard"** page
2. View **"Staking Orders"** list, switch tabs:
   - **Depositing/Redeemable**: Active orders
   - **Redeemed**: Historical orders
3. Each order shows:
   - Deposit amount
   - Deposit time
   - Redeemable time
   - Status (Depositing / Redeemable)

![Staking Orders](./images/stake-orders.png)

---

## Redeem Stake

After staking order matures, redeem assets within grace period.

### 7.1 Redemption Timeline

```
Stake Start ────── Stake Period ──────> Maturity ────── 72hr Grace ──────> Auto-renewal
            Earning rewards                Redemption window         Cannot redeem, restarts next cycle
```

> Testnet stake period is 7 days. Mainnet stake period is TBD.

### 7.2 Check Redeemable Orders

1. Go to node **"Dashboard"** page
2. In **"Staking Orders"** list
3. Orders with **"Redeemable"** status can be redeemed

### 7.3 Generate Redemption Signature

```bash
cd ~/pijs-node

geth hybrid bls redeem \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --orderid 1 \
  --withdrawal 0xYourWithdrawalAddress \
  --recipient 0xYourRecipientAddress \
  --output redeem_data.json

# Parameter description:
# --orderid     : Order ID (view from Web interface)
# --withdrawal  : Withdrawal address (must match staking)
# --recipient   : Fund receiving address (can be any address)
```

### 7.4 Redeem on Web Platform

1. On node **"Dashboard"** page
2. Expand **"Stake Redemption"** section
3. Click **"Upload redeem_data.json"** area
4. Select the redemption signature file just generated
5. Click **"Submit"** button
6. Confirm transaction in wallet

![Redeem Stake](./images/redeem.png)

### 7.5 Verify Redemption Success

After successful redemption:

- Order status changes to **"Redeemed"**
- Funds transferred to specified `recipient` address
- Order's stake amount deducted from node's total stake

---

## FAQ

### What is a Validator (Node)?

A validator is a virtual entity on the beacon chain, represented by balance, public key, and other attributes. It participates in the consensus process of the PIJSChain network.

### What is a Validator Client?

A validator client is software that performs operations on behalf of the validator by storing and using the validator's private key to authenticate chain state.

### What is a Node Operator?

A node operator is a person who ensures the client software runs properly and maintains the hardware as needed.

### How much PIJS do I need to stake to become a validator?

| Network | Minimum Stake | Maximum Stake |
|---------|---------------|---------------|
| Testnet | 2,000 PIJS    | 100,000 PIJS  |
| Mainnet | TBD           | TBD           |

Amounts exceeding the maximum stake do not participate in reward calculations.

> ⚠️ Mainnet staking rules are TBD. Subject to official announcements.

### Why stake PIJS?

As a validator, you need funds at stake to be penalized for dishonest behavior. In other words, to keep you honest, your actions need to have financial consequences.

### What are validator rewards?

Validators receive PIJS token rewards based on their staking network weight.

### When can I withdraw my staked PIJS?

After staking matures, you can unlock within **72 hours**. If not unlocked within 72 hours, it automatically enters the next cycle. Testnet stake period is 7 days. Mainnet stake period is TBD.

### How are PIJSChain staking rewards settled?

PIJSChain staking settlement is **daily**. Rewards generated from the previous day's network consensus are distributed to corresponding withdrawal addresses the next day.

### Why does the APY change?

The yield is related to your stake amount and network consensus weight.

### Will I be slashed if I go offline?

**No**. When you are offline or the network cannot verify you are online, it means you cannot participate in PIJSChain network consensus. Staking rewards will stop until you can rejoin consensus. **Your principal will not be deducted**.

### What is a withdrawal address?

The address used to receive your staking rewards.

### Can I change my withdrawal address?

**No**. The withdrawal address is determined at the time of first staking and cannot be modified. You must use the same withdrawal address to sign when redeeming.

### How do I withdraw my staking rewards?

No manual withdrawal needed. Rewards are **automatically sent to your withdrawal address** by the network based on stake amount and consensus weight.

### How do I unlock my staked PIJS?

Sign the system's random Challenge value with your BLS private key, submit the signature to the network, and after verification you will receive your staked PIJS.

### What is Node Claiming (Easy Management)?

Node Claiming proves you own the validator's private key through BLS signature, thereby associating the validator with your wallet address. After association, you can:

- ✅ View detailed validator information in the Web interface
- ✅ Manage validator staking orders
- ✅ Perform add stake, redeem, and other operations

### What happens if I forget or lose my BLS key?

If you lose your signing key, your validator will be **unable to continue staking and withdraw funds**. Please make sure to backup your key file and password securely.

### How to prevent phishing attacks?

1. **Carefully check the URL** - Are there any spelling errors?
2. **Cross-check contract addresses** - Verify deposit contract address against other official websites
3. **Verify contract address before signing** - Check carefully in your wallet
4. **Check the complete address** - Don't just check part of it; there may be only a few bytes difference

---

## Quick Command Reference

### BLS Key Management

```bash
# Generate key
geth hybrid bls generate --save ./bls-keystore.json

# View public key
geth hybrid bls show --keyfile ./bls-keystore.json

# Import existing private key
geth hybrid bls import --privkey 0x... --save ./bls-keystore.json
```

### Signature Generation

```bash
# Staking signature (Standard Mode)
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0x... \
  --amount 10000 \
  --output deposit_data.json

# Staking signature (Operator Mode - with separate withdrawal address)
geth hybrid bls deposit \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --address 0x... \
  --withdrawal 0x... \
  --amount 10000 \
  --output deposit_data.json

# Claim signature
geth hybrid bls sign \
  --keyfile ./keys/bls-keystore.json \
  --message 0x... \
  --output easy_management_setup.json

# Redemption signature
geth hybrid bls redeem \
  --keyfile ./keys/bls-keystore.json \
  --chainid 20250521 \
  --orderid 1 \
  --withdrawal 0x... \
  --recipient 0x... \
  --output redeem_data.json
```

### Node Operations

```bash
# Connect console
geth attach ./data/geth.ipc

# Check sync status
> eth.syncing

# Check block height
> eth.blockNumber

# Check peer nodes
> net.peerCount

# Check node identity
> hybrid.getNodeBLSIdentity()

# Check liveness status
> hybrid.getLivenessStatus()
```

---

## Get Help

- Support Email: [support@pijschain.com]
