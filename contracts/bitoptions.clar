;; Title: 
;; BitOptions: Decentralized Options Trading Protocol on Stacks L2
;; Summary: 
;; Bitcoin-native options trading platform with SIP-010 compliance, offering secure financial derivatives
;; Description:
;; BitOptions is a Layer-2 decentralized options protocol built on Stacks, enabling trustless trading of 
;; Bitcoin-native financial derivatives. The platform features:
;; - SIP-010 compliant options contracts with multi-asset support
;; - Collateralized European-style options (Call/Put)
;; - Integrated price oracle system with decentralized feed updates
;; - Protocol-level risk management with dynamic collateral requirements
;; - Governance-controlled fee structure and token whitelisting
;; - Bitcoin settlement compatibility with Stacks L2 security guarantees

;; Designed for institutional-grade DeFi, BitOptions implements:
;; 1. Non-custodial collateral management
;; 2. Time-decay optimized contract expiration
;; 3. Strike price validation against decentralized oracles
;; 4. Regulatory-compliant position tracking
;; 5. Cross-chain compatibility via Bitcoin-anchored assets

(define-trait sip-010-trait
    (
        ;; SIP-010 Standard Token Interface
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-balance (principal) (response uint uint))
        (get-total-supply () (response uint uint))
        (get-decimals () (response uint uint))
        (get-token-uri () (response (optional (string-utf8 256)) uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
    )
)

;; Error codes optimized for regulatory reporting
(define-constant ERR-NOT-AUTHORIZED (err u1000))   ;; Unauthorized access attempt
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))  ;; Insufficient token balance
(define-constant ERR-INVALID-EXPIRY (err u1002))   ;; Expiration time validation failed
(define-constant ERR-INVALID-STRIKE-PRICE (err u1003))  ;; Invalid strike price input
(define-constant ERR-OPTION-NOT-FOUND (err u1004))  ;; Non-existent option reference
(define-constant ERR-OPTION-EXPIRED (err u1005))   ;; Attempt to trade expired contract
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1006)) ;; Margin requirement not met
(define-constant ERR-ALREADY-EXERCISED (err u1007))  ;; Duplicate contract exercise attempt
(define-constant ERR-INVALID-PREMIUM (err u1008))  ;; Premium pricing violation

;; Enhanced validation errors
(define-constant ERR-INVALID-TOKEN (err u1009))  ;; Unapproved token usage
(define-constant ERR-INVALID-SYMBOL (err u1010))  ;; Invalid oracle symbol format
(define-constant ERR-INVALID-TIMESTAMP (err u1011))  ;; Time synchronization failure
(define-constant ERR-INVALID-ADDRESS (err u1012))  ;; Malformed principal address
(define-constant ERR-ZERO-ADDRESS (err u1013))  ;; Null address prohibited
(define-constant ERR-EMPTY-SYMBOL (err u1014))  ;; Missing required symbol parameter

;; Core Protocol Storage
(define-map options  ;; Active options registry
    uint  ;; Option ID
    {
        writer: principal,  ;; Option seller
        holder: (optional principal),  ;; Option buyer
        collateral-amount: uint,  ;; Collateral locked
        strike-price: uint,  ;; Strike price in satoshis
        premium: uint,  ;; Premium amount
        expiry: uint,  ;; Bitcoin block height expiration
        is-exercised: bool,  ;; Execution status
        option-type: (string-ascii 4),  ;; "CALL"/"PUT"
        state: (string-ascii 9)  ;; "ACTIVE"/"EXERCISED"
    }
)

(define-map user-positions  ;; Risk management ledger
    principal  ;; Trader address
    {
        written-options: (list 10 uint),  ;; Sold contracts
        held-options: (list 10 uint),  ;; Purchased rights
        total-collateral-locked: uint  ;; Active margin
    }
)

;; Protocol Configuration
(define-map approved-tokens  ;; SIP-010 whitelist
    principal  ;; Token contract address
    bool
)

(define-data-var next-option-id uint u1)  ;; Monotonic ID counter
(define-data-var contract-owner principal tx-sender)  ;; Governance admin
(define-data-var protocol-fee-rate uint u100)  ;; 1% in basis points

;; Price Oracle Registry
(define-map price-feeds  ;; Decentralized price data
    (string-ascii 10)  ;; Trading pair (e.g., "BTC-USD")
    {
        price: uint,  ;; Scaled price value
        timestamp: uint,  ;; Last update time
        source: principal  ;; Oracle provider
    }
)

(define-map allowed-symbols  ;; Valid trading pairs
    (string-ascii 10)  ;; Symbol format
    bool
)


;; Utility Functions
(define-private (get-min (a uint) (b uint))
    (if (< a b) a b))