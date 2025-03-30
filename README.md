# BitOptions Smart Contract Documentation

## Overview

BitOptions is a decentralized options trading protocol built on Stacks L2, enabling trustless creation and execution of Bitcoin-native financial derivatives. The contract implements European-style options with SIP-010 token compliance and institutional-grade risk management.

## Key Features

- **SIP-010 Multi-Asset Support**: Native integration with Stacks token standard
- **Collateralized Options**: Non-custodial margin system with dynamic requirements
- **Price Oracle System**: Decentralized feed updates for strike price validation
- **European Exercise Style**: Time-bound expiration with BTC-block height alignment
- **Governance Controls**: Configurable protocol fees and asset whitelisting
- **Regulatory Compliance**: Position tracking and audit-ready error codes

## Technical Specifications

### Contract Basics

- **Language**: Clarity v2.1
- **Standard**: SIP-010 Token Interface
- **Error Codes**: 15 defined error states with regulatory mapping
- **Storage**: 6 persistent maps, 3 data variables

### Core Components

#### 1. Options Registry (`options` map)

```clarity
{
    writer: principal,
    holder: (optional principal),
    collateral-amount: uint,
    strike-price: uint,
    premium: uint,
    expiry: uint,
    is-exercised: bool,
    option-type: (string-ascii 4),  // "CALL"/"PUT"
    state: (string-ascii 9)         // "ACTIVE"/"EXERCISED"
}
```

#### 2. User Positions (`user-positions` map)

```clarity
{
    written-options: (list 10 uint),
    held-options: (list 10 uint),
    total-collateral-locked: uint
}
```

#### 3. Approved Tokens (`approved-tokens` map)

- Principal → bool mapping for SIP-010 whitelist

#### 4. Price Oracle (`price-feeds` map)

```clarity
{
    price: uint,       // 8-decimal precision
    timestamp: uint,   // BTC block height
    source: principal  // Verified oracle
}
```

## Workflow Overview

### 1. Option Creation

```clarity
(write-option
    token<sip-010-trait>
    collateral-amount<uint>
    strike-price<uint>
    premium<uint>
    expiry<uint>
    option-type<string-ascii-4>
)
```

- Validates collateral against strike price
- Locks tokens using SIP-010 transfer
- Generates unique option ID

### 2. Option Purchase

```clarity
(buy-option
    token<sip-010-trait>
    option-id<uint>
)
```

- Transfers premium to writer
- Updates holder position
- Validates expiration time

### 3. Option Exercise

```clarity
(exercise-option
    token<sip-010-trait>
    option-id<uint>
)
```

- Verifies holder authorization
- Checks price oracle validity
- Executes profit calculation:
  - Call: max(0, spot - strike)
  - Put: max(0, strike - spot)
- Distributes collateral proportionally

## Admin Functions

### 1. Protocol Configuration

```clarity
(set-protocol-fee-rate new-rate<uint>)
```

- Requires: Contract owner
- Range: 0-1000 (0-10% in basis points)

### 2. Oracle Management

```clarity
(update-price-feed
    symbol<string-ascii-10>
    price<uint>
    timestamp<uint>
)
```

- Requires: Approved oracle source
- Validates: Future timestamp rejection

### 3. Asset Management

```clarity
(set-approved-token token<principal> approved<bool>)
(set-allowed-symbol symbol<string-ascii-10> allowed<bool>)
```

- Whitelist control for tokens/pairs
- Critical asset protection mechanisms

## Security Model

### 1. Clarity Benefits

- Predictable execution costs
- Static analysis compatibility
- Bitcoin-finalized state transitions

### 2. Input Validation

- Principal address checks
- Timestamp future-proofing
- Collateral adequacy verification

### 3. Access Control

- Owner-restricted configuration
- Oracle source whitelisting
- Critical function protections

## Contributing

### 1. Development Setup

```bash
git clone https://github.com/bitoptions/core-contracts
```

### 2. Governance Process

1. Draft SIP proposal
2. Security review
3. Testnet deployment
4. Community voting

## References

1. SIP-010 Token Standard
2. Stacks Blockchain Documentation
