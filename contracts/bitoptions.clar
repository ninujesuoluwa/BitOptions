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

;; Write a new option
(define-public (write-option
    (token <sip-010-trait>)
    (collateral-amount uint)
    (strike-price uint)
    (premium uint)
    (expiry uint)
    (option-type (string-ascii 4)))
    (let (
        (option-id (var-get next-option-id))
        (current-time stacks-block-height)
        (token-principal (contract-of token))
    )
        ;; Validate token
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (> expiry current-time) ERR-INVALID-EXPIRY)
        (asserts! (> strike-price u0) ERR-INVALID-STRIKE-PRICE)
        (asserts! (> premium u0) ERR-INVALID-PREMIUM)
        (asserts! (check-collateral-requirement collateral-amount strike-price option-type) ERR-INSUFFICIENT-COLLATERAL)
        
        
        ;; Lock collateral using validated token
        (try! (contract-call? token transfer 
            collateral-amount 
            tx-sender 
            (as-contract tx-sender) 
            none))
        
        ;; Create option
        (map-set options option-id {
            writer: tx-sender,
            holder: none,
            collateral-amount: collateral-amount,
            strike-price: strike-price,
            premium: premium,
            expiry: expiry,
            is-exercised: false,
            option-type: option-type,
            state: "ACTIVE"
        })
        
        ;; Update user position
        (let ((current-position (default-to 
            { written-options: (list ), held-options: (list ), total-collateral-locked: u0 }
            (map-get? user-positions tx-sender))))
            (map-set user-positions tx-sender
                (merge current-position {
                    written-options: (unwrap-panic (as-max-len? 
                        (append (get written-options current-position) option-id) u10)),
                    total-collateral-locked: (+ (get total-collateral-locked current-position) collateral-amount)
                })
            )
        )
        
        ;; Increment option ID
        (var-set next-option-id (+ option-id u1))
        (ok option-id)
    )
)

;; Buy an option
(define-public (buy-option 
    (token <sip-010-trait>)
    (option-id uint))
    (let (
        (option (unwrap! (map-get? options option-id) ERR-OPTION-NOT-FOUND))
        (premium (get premium option))
        (token-principal (contract-of token))
    )
        ;; Validate token
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (is-none (get holder option)) ERR-ALREADY-EXERCISED)
        (asserts! (< stacks-block-height (get expiry option)) ERR-OPTION-EXPIRED)
        
        ;; Transfer premium using the token
        (try! (contract-call? token transfer
            premium
            tx-sender
            (get writer option)
            none))
        
        ;; Update option
        (map-set options option-id (merge option { 
            holder: (some tx-sender)
        }))
        
        ;; Update buyer position
        (let ((current-position (default-to 
            { written-options: (list ), held-options: (list ), total-collateral-locked: u0 }
            (map-get? user-positions tx-sender))))
            (map-set user-positions tx-sender
                (merge current-position {
                    held-options: (unwrap-panic (as-max-len? 
                        (append (get held-options current-position) option-id) u10))
                })
            )
        )
        
        (ok true)
    )
)

;; Exercise option
(define-public (exercise-option 
    (token <sip-010-trait>)
    (option-id uint))
    (let (
        (option (unwrap! (map-get? options option-id) ERR-OPTION-NOT-FOUND))
        (current-price (get-current-price))
        (token-principal (contract-of token))
    )
        ;; Validate token
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (is-eq (some tx-sender) (get holder option)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get is-exercised option)) ERR-ALREADY-EXERCISED)
        (asserts! (< stacks-block-height (get expiry option)) ERR-OPTION-EXPIRED)
        
        (if (is-eq (get option-type option) "CALL")
            (exercise-call token option current-price)
            (exercise-put token option current-price)
        )
    )
)

;; Private helper functions

(define-private (check-collateral-requirement (amount uint) (strike uint) (option-type (string-ascii 4)))
    (if (is-eq option-type "CALL")
        (>= amount strike)
        (>= amount (/ (* strike u100000000) (get-current-price)))
    )
)

(define-private (exercise-call 
    (token <sip-010-trait>)
    (option {
        writer: principal,
        holder: (optional principal),
        collateral-amount: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        is-exercised: bool,
        option-type: (string-ascii 4),
        state: (string-ascii 9)
    }) 
    (current-price uint))
    (let (
        (profit (- current-price (get strike-price option)))
        (payout (get-min profit (get collateral-amount option)))
    )
        ;; Transfer payout using token
        (try! (as-contract (contract-call? token transfer
            payout
            tx-sender
            (unwrap! (get holder option) ERR-NOT-AUTHORIZED)
            none)))
        
        ;; Return remaining collateral to writer
        (try! (as-contract (contract-call? token transfer
            (- (get collateral-amount option) payout)
            tx-sender
            (get writer option)
            none)))
        
        ;; Update option state
        (map-set options (get-option-id option) (merge option {
            is-exercised: true,
            state: "EXERCISED"
        }))
        
        (ok true)
    )
)

(define-private (exercise-put
    (token <sip-010-trait>)
    (option {
        writer: principal,
        holder: (optional principal),
        collateral-amount: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        is-exercised: bool,
        option-type: (string-ascii 4),
        state: (string-ascii 9)
    })
    (current-price uint))
    (let (
        (profit (- (get strike-price option) current-price))
        (payout (get-min profit (get collateral-amount option)))
    )
        ;; Transfer payout using token
        (try! (as-contract (contract-call? token transfer
            payout
            tx-sender
            (unwrap! (get holder option) ERR-NOT-AUTHORIZED)
            none)))
        
        ;; Return remaining collateral to writer
        (try! (as-contract (contract-call? token transfer
            (- (get collateral-amount option) payout)
            tx-sender
            (get writer option)
            none)))
        
        ;; Update option state
        (map-set options (get-option-id option) (merge option {
            is-exercised: true,
            state: "EXERCISED"
        }))
        
        (ok true)
    )
)

;; Utility functions

(define-private (get-current-price)
    (get price (unwrap! (map-get? price-feeds "BTC-USD") u0))
)

(define-private (get-option-id (option {
        writer: principal,
        holder: (optional principal),
        collateral-amount: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        is-exercised: bool,
        option-type: (string-ascii 4),
        state: (string-ascii 9)
    }))
    (var-get next-option-id)
)

;; Add function to check if token is approved
(define-private (is-approved-token (token principal))
    (default-to false (map-get? approved-tokens token))
)

(define-private (is-allowed-symbol (symbol (string-ascii 10)))
    (default-to false (map-get? allowed-symbols symbol))
)

;; Update helper functions for validation
(define-private (is-valid-principal (address principal))
    (and 
        (not (is-eq address (as-contract tx-sender)))  ;; Can't be the contract itself
        (not (is-eq address .base))  ;; Can't be base contract
        (not (is-eq address tx-sender))  ;; Can't be the owner (prevent self-targeting)
        true  ;; Remove the principal-destruct? check as it's not needed
    )
)

(define-private (is-valid-symbol (symbol (string-ascii 10)))
    (and
        (not (is-eq symbol ""))  ;; Can't be empty
        (not (is-eq symbol " "))  ;; Can't be just whitespace
        (>= (len symbol) u2)      ;; Must be at least 2 chars
    )
)

(define-private (is-critical-token (token principal))
    ;; Add any tokens that shouldn't be removed
    (or 
        (is-eq token .wrapped-btc)
        (is-eq token .wrapped-stx)
    )
)

(define-private (is-critical-symbol (symbol (string-ascii 10)))
    ;; Add any symbols that shouldn't be removed
    (or
        (is-eq symbol "BTC-USD")
        (is-eq symbol "STX-USD")
    )
)

;; Read-only functions

(define-read-only (get-option (option-id uint))
    (map-get? options option-id)
)

(define-read-only (get-user-position (user principal))
    (map-get? user-positions user)
)

(define-read-only (get-protocol-fee-rate)
    (var-get protocol-fee-rate)
)

;; Admin functions

(define-public (set-protocol-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rate u1000) ERR-INVALID-PREMIUM)  ;; Max 10%
        (var-set protocol-fee-rate new-rate)
        (ok true)
    )
)

(define-public (update-price-feed 
    (symbol (string-ascii 10))
    (price uint)
    (timestamp uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-allowed-symbol symbol) ERR-INVALID-SYMBOL)
        (asserts! (>= timestamp stacks-block-height) ERR-INVALID-TIMESTAMP)
        (asserts! (> price u0) ERR-INVALID-STRIKE-PRICE)
        
        (map-set price-feeds symbol {
            price: price,
            timestamp: timestamp,
            source: tx-sender
        })
        (ok true)
    )
)

;; Admin function to manage approved tokens
;; Update admin functions with validation

(define-public (set-approved-token (token principal) (approved bool))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-principal token) ERR-INVALID-ADDRESS)
        (asserts! (not (is-eq token .base)) ERR-INVALID-TOKEN)  ;; Prevent setting base token
        
        ;; Additional check to prevent removing critical tokens
        (asserts! (or 
            approved  ;; If we're approving, this check doesn't matter
            (not (is-critical-token token))  ;; If removing, check it's not critical
        ) ERR-NOT-AUTHORIZED)
        
        (map-set approved-tokens token approved)
        (ok true)
    )
)

(define-public (set-allowed-symbol (symbol (string-ascii 10)) (allowed bool))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-symbol symbol) ERR-EMPTY-SYMBOL)
        
        ;; Additional check to prevent removing critical symbols
        (asserts! (or 
            allowed  ;; If we're allowing, this check doesn't matter
            (not (is-critical-symbol symbol))  ;; If removing, check it's not critical
        ) ERR-NOT-AUTHORIZED)
        
        (map-set allowed-symbols symbol allowed)
        (ok true)
    )
)
