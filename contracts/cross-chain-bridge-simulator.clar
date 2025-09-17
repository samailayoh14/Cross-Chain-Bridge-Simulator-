(define-fungible-token bridge-token)

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-CHAIN (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-ALREADY-PROCESSED (err u104))
(define-constant ERR-INVALID-RECIPIENT (err u105))
(define-constant ERR-CHAIN-NOT-SUPPORTED (err u106))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-CHAINS u10)
(define-constant MIN-BRIDGE-AMOUNT u1000000)

(define-data-var total-chains uint u0)
(define-data-var bridge-fee uint u10000)
(define-data-var is-bridge-active bool true)

(define-map chain-registry 
    { chain-id: uint } 
    { 
        name: (string-ascii 20),
        is-active: bool,
        total-locked: uint,
        total-minted: uint
    }
)

(define-map user-balances
    { user: principal, chain-id: uint }
    { 
        locked: uint,
        wrapped: uint
    }
)

(define-map cross-chain-transactions
    { tx-id: (buff 32) }
    {
        from-chain: uint,
        to-chain: uint,
        sender: principal,
        recipient: principal,
        amount: uint,
        processed: bool,
        block-height: uint
    }
)

(define-map chain-validators
    { chain-id: uint, validator: principal }
    { is-active: bool }
)

(define-private (is-valid-chain (chain-id uint))
    (match (map-get? chain-registry { chain-id: chain-id })
        chain-info (get is-active chain-info)
        false
    )
)

(define-private (get-user-balance (user principal) (chain-id uint) (balance-type (string-ascii 10)))
    (match (map-get? user-balances { user: user, chain-id: chain-id })
        balance-info 
            (if (is-eq balance-type "locked")
                (get locked balance-info)
                (get wrapped balance-info)
            )
        u0
    )
)

(define-private (update-user-balance (user principal) (chain-id uint) (locked-amount uint) (wrapped-amount uint))
    (map-set user-balances
        { user: user, chain-id: chain-id }
        { locked: locked-amount, wrapped: wrapped-amount }
    )
)

(define-private (update-chain-totals (chain-id uint) (locked-delta int) (minted-delta int))
    (match (map-get? chain-registry { chain-id: chain-id })
        chain-info
            (map-set chain-registry
                { chain-id: chain-id }
                {
                    name: (get name chain-info),
                    is-active: (get is-active chain-info),
                    total-locked: (+ (get total-locked chain-info) (if (>= locked-delta 0) (to-uint locked-delta) (- (get total-locked chain-info) (to-uint (- locked-delta))))),
                    total-minted: (+ (get total-minted chain-info) (if (>= minted-delta 0) (to-uint minted-delta) (- (get total-minted chain-info) (to-uint (- minted-delta)))))
                }
            )
        false
    )
)

(define-public (register-chain (chain-id uint) (name (string-ascii 20)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (< (var-get total-chains) MAX-CHAINS) ERR-INVALID-CHAIN)
        (asserts! (is-none (map-get? chain-registry { chain-id: chain-id })) ERR-INVALID-CHAIN)
        
        (map-set chain-registry
            { chain-id: chain-id }
            {
                name: name,
                is-active: true,
                total-locked: u0,
                total-minted: u0
            }
        )
        (var-set total-chains (+ (var-get total-chains) u1))
        (ok chain-id)
    )
)

(define-public (add-validator (chain-id uint) (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN)
        
        (map-set chain-validators
            { chain-id: chain-id, validator: validator }
            { is-active: true }
        )
        (ok true)
    )
)

(define-public (lock-tokens (chain-id uint) (amount uint))
    (let
        (
            (current-locked (get-user-balance tx-sender chain-id "locked"))
            (current-balance (ft-get-balance bridge-token tx-sender))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN)
        (asserts! (>= amount MIN-BRIDGE-AMOUNT) ERR-INVALID-AMOUNT)
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        (try! (ft-burn? bridge-token amount tx-sender))
        (update-user-balance tx-sender chain-id (+ current-locked amount) (get-user-balance tx-sender chain-id "wrapped"))
        (update-chain-totals chain-id (to-int amount) 0)
        (ok amount)
    )
)

(define-public (unlock-tokens (chain-id uint) (amount uint))
    (let
        (
            (current-locked (get-user-balance tx-sender chain-id "locked"))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN)
        (asserts! (>= current-locked amount) ERR-INSUFFICIENT-BALANCE)
        
        (try! (ft-mint? bridge-token amount tx-sender))
        (update-user-balance tx-sender chain-id (- current-locked amount) (get-user-balance tx-sender chain-id "wrapped"))
        (update-chain-totals chain-id (- (to-int amount)) 0)
        (ok amount)
    )
)

(define-public (mint-wrapped (chain-id uint) (amount uint) (recipient principal))
    (let
        (
            (current-wrapped (get-user-balance recipient chain-id "wrapped"))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN)
        (asserts! (>= amount MIN-BRIDGE-AMOUNT) ERR-INVALID-AMOUNT)
        
        (update-user-balance recipient chain-id (get-user-balance recipient chain-id "locked") (+ current-wrapped amount))
        (update-chain-totals chain-id 0 (to-int amount))
        (ok amount)
    )
)

(define-public (burn-wrapped (chain-id uint) (amount uint))
    (let
        (
            (current-wrapped (get-user-balance tx-sender chain-id "wrapped"))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN)
        (asserts! (>= current-wrapped amount) ERR-INSUFFICIENT-BALANCE)
        
        (update-user-balance tx-sender chain-id (get-user-balance tx-sender chain-id "locked") (- current-wrapped amount))
        (update-chain-totals chain-id 0 (- (to-int amount)))
        (ok amount)
    )
)

(define-public (bridge-transfer (from-chain uint) (to-chain uint) (amount uint) (recipient principal))
    (let
        (
            (tx-id (keccak256 (concat (concat (unwrap-panic (to-consensus-buff? tx-sender)) (unwrap-panic (to-consensus-buff? block-height))) (unwrap-panic (to-consensus-buff? amount)))))
            (current-locked (get-user-balance tx-sender from-chain "locked"))
            (fee-amount (/ (* amount (var-get bridge-fee)) u1000000))
            (transfer-amount (- amount fee-amount))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain from-chain) ERR-INVALID-CHAIN)
        (asserts! (is-valid-chain to-chain) ERR-INVALID-CHAIN)
        (asserts! (not (is-eq from-chain to-chain)) ERR-INVALID-CHAIN)
        (asserts! (>= amount MIN-BRIDGE-AMOUNT) ERR-INVALID-AMOUNT)
        (asserts! (>= current-locked amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (is-none (map-get? cross-chain-transactions { tx-id: tx-id })) ERR-ALREADY-PROCESSED)
        
        (update-user-balance tx-sender from-chain (- current-locked amount) (get-user-balance tx-sender from-chain "wrapped"))
        (try! (mint-wrapped to-chain transfer-amount recipient))
        
        (map-set cross-chain-transactions
            { tx-id: tx-id }
            {
                from-chain: from-chain,
                to-chain: to-chain,
                sender: tx-sender,
                recipient: recipient,
                amount: amount,
                processed: true,
                block-height: block-height
            }
        )
        (ok tx-id)
    )
)

(define-public (set-bridge-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set bridge-fee new-fee)
        (ok new-fee)
    )
)

(define-public (toggle-bridge)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set is-bridge-active (not (var-get is-bridge-active)))
        (ok (var-get is-bridge-active))
    )
)

(define-public (mint-initial-tokens (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ft-mint? bridge-token amount tx-sender)
    )
)

(define-read-only (get-chain-info (chain-id uint))
    (map-get? chain-registry { chain-id: chain-id })
)

(define-read-only (get-user-chain-balance (user principal) (chain-id uint))
    (map-get? user-balances { user: user, chain-id: chain-id })
)

(define-read-only (get-transaction (tx-id (buff 32)))
    (map-get? cross-chain-transactions { tx-id: tx-id })
)

(define-read-only (get-bridge-fee)
    (var-get bridge-fee)
)

(define-read-only (get-bridge-status)
    (var-get is-bridge-active)
)

(define-read-only (get-total-chains)
    (var-get total-chains)
)

(define-read-only (is-validator (chain-id uint) (validator principal))
    (match (map-get? chain-validators { chain-id: chain-id, validator: validator })
        validator-info (get is-active validator-info)
        false
    )
)