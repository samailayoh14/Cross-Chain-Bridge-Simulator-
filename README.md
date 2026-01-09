# 🌉 Cross-Chain Bridge Simulator

> **Simulate cross-chain token transfers and learn blockchain interoperability! 🚀**

## 📖 Overview

The Cross-Chain Bridge Simulator is a Clarity smart contract that demonstrates how tokens can be moved between different blockchain networks. This educational tool teaches the fundamental concepts of cross-chain interoperability through a lock-and-mint mechanism.

## ✨ Features

- 🔒 **Token Locking**: Lock tokens on the source chain
- 🪙 **Wrapped Token Minting**: Mint wrapped tokens on destination chains  
- 🔥 **Token Burning**: Burn wrapped tokens to unlock originals
- 🌐 **Multi-Chain Support**: Register and manage multiple chains
- 💰 **Bridge Fees**: Configurable transaction fees
- 👥 **Validator System**: Chain-specific validator management
- 📊 **Transaction Tracking**: Complete cross-chain transaction history

## 🏗️ Architecture

```
Source Chain          Bridge Contract         Destination Chain
     |                       |                        |
 [Lock STX] ────────────> [Validate] ───────────> [Mint wSTX]
     |                       |                        |
[Unlock STX] <────────────[Process] <───────────── [Burn wSTX]
```

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Basic understanding of Clarity smart contracts

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd Cross-Chain-Bridge-Simulator
```

2. Install dependencies:
```bash
npm install
```

3. Deploy the contract:
```bash
clarinet deploy
```

## 📋 Usage Examples

### 🏭 Admin Functions

#### Register a New Chain
```clarity
(contract-call? .cross-chain-bridge-simulator register-chain u1 "ethereum")
(contract-call? .cross-chain-bridge-simulator register-chain u2 "polygon")
```

#### Add Chain Validator
```clarity
(contract-call? .cross-chain-bridge-simulator add-validator u1 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

#### Mint Initial Tokens
```clarity
(contract-call? .cross-chain-bridge-simulator mint-initial-tokens u1000000000)
```

### 💼 User Functions

#### Lock Tokens for Cross-Chain Transfer
```clarity
(contract-call? .cross-chain-bridge-simulator lock-tokens u1 u5000000)
```

#### Bridge Transfer Between Chains
```clarity
(contract-call? .cross-chain-bridge-simulator bridge-transfer 
  u1 u2 u3000000 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

#### Unlock Original Tokens
```clarity
(contract-call? .cross-chain-bridge-simulator unlock-tokens u1 u2000000)
```

#### Burn Wrapped Tokens
```clarity
(contract-call? .cross-chain-bridge-simulator burn-wrapped u2 u1000000)
```

### 📊 Read-Only Functions

#### Check Chain Information
```clarity
(contract-call? .cross-chain-bridge-simulator get-chain-info u1)
```

#### Get User Balance on Chain
```clarity
(contract-call? .cross-chain-bridge-simulator get-user-chain-balance 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u1)
```

#### Check Bridge Status
```clarity
(contract-call? .cross-chain-bridge-simulator get-bridge-status)
```

## 🎯 Core Concepts

### 🔐 Lock & Mint Mechanism
1. **Lock**: Users lock original tokens on source chain
2. **Mint**: Equivalent wrapped tokens are minted on destination chain
3. **Burn**: Wrapped tokens are burned on destination chain
4. **Unlock**: Original tokens are unlocked on source chain

### ⛓️ Chain Registry
- Each supported chain has a unique ID
- Tracks total locked and minted tokens
- Admin-controlled activation/deactivation

### 💳 User Balances
- **Locked Balance**: Original tokens locked on source chains
- **Wrapped Balance**: Wrapped tokens on destination chains
- Separate tracking per user per chain

### 🛡️ Security Features
- Minimum bridge amount requirements
- Transaction uniqueness validation
- Owner-only administrative functions
- Bridge pause/resume functionality

## ⚙️ Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MIN-BRIDGE-AMOUNT` | 1,000,000 | Minimum tokens for bridge operations |
| `MAX-CHAINS` | 10 | Maximum supported chains |
| `bridge-fee` | 10,000 | Fee in basis points (1% = 10,000) |

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🎓 Educational Value

This simulator teaches:
- Cross-chain bridge mechanics
- Token locking and minting patterns
- Multi-chain state management
- Validator coordination
- Transaction lifecycle management

Perfect for developers learning blockchain interoperability! 🎯

---

**Happy Bridging! 🌈✨**
