(define-fungible-token bridge-token)

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-CHAIN (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-ALREADY-PROCESSED (err u104))
(define-constant ERR-INVALID-RECIPIENT (err u105))
(define-constant ERR-CHAIN-NOT-SUPPORTED (err u106))
(define-constant ERR-WITHDRAWAL-NOT-FOUND (err u107))
(define-constant ERR-WITHDRAWAL-LOCKED (err u108))
(define-constant ERR-WITHDRAWAL-ALREADY-CLAIMED (err u109))
(define-constant ERR-ALLOWANCE-INSUFFICIENT (err u110))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-CHAINS u10)
(define-constant MIN-BRIDGE-AMOUNT u1000000)
(define-constant DEFAULT-TIMELOCK-BLOCKS u144)

(define-data-var total-chains uint u0)
(define-data-var bridge-fee uint u10000)
(define-data-var is-bridge-active bool true)
(define-data-var withdrawal-counter uint u0)

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
    { user: principal, balance-chain-id: uint }
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
    { validator-chain-id: uint, validator: principal }
    { is-active: bool }
)

(define-map chain-timelocks
    { timelock-chain-id: uint }
    { timelock-blocks: uint }
)

(define-map withdrawal-queue
    { withdrawal-id: uint }
    {
        user: principal,
        target-chain-id: uint,
        amount: uint,
        requested-at: uint,
        unlock-at: uint,
        claimed: bool
    }
)

(define-map user-withdrawal-ids
    { user: principal, user-chain-id: uint }
    { withdrawal-ids: (list 50 uint) }
)

(define-map allowances
    { owner: principal, spender: principal }
    { amount: uint }
)

(define-private (is-valid-chain (cid uint))
    (match (map-get? chain-registry { chain-id: cid })
        chain-info (get is-active chain-info)
        false
    )
)

(define-private (get-user-balance (user principal) (cid uint) (balance-type (string-ascii 10)))
    (match (map-get? user-balances { user: user, balance-chain-id: cid })
        balance-info 
            (if (is-eq balance-type "locked")
                (get locked balance-info)
                (get wrapped balance-info)
            )
        u0
    )
)

(define-private (update-user-balance (user principal) (cid uint) (locked-amount uint) (wrapped-amount uint))
    (map-set user-balances
        { user: user, balance-chain-id: cid }
        { locked: locked-amount, wrapped: wrapped-amount }
    )
)

(define-private (update-chain-totals (cid uint) (locked-delta int) (minted-delta int))
    (match (map-get? chain-registry { chain-id: cid })
        chain-info
            (map-set chain-registry
                { chain-id: cid }
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

(define-private (get-chain-timelock (cid uint))
    (match (map-get? chain-timelocks { timelock-chain-id: cid })
        timelock-info (get timelock-blocks timelock-info)
        DEFAULT-TIMELOCK-BLOCKS
    )
)

(define-private (add-withdrawal-id-to-user (user principal) (cid uint) (withdrawal-id uint))
    (let
        (
            (current-ids (default-to (list) (get withdrawal-ids (map-get? user-withdrawal-ids { user: user, user-chain-id: cid }))))
        )
        (map-set user-withdrawal-ids
            { user: user, user-chain-id: cid }
            { withdrawal-ids: (unwrap-panic (as-max-len? (append current-ids withdrawal-id) u50)) }
        )
    )
)

(define-public (register-chain (cid uint) (name (string-ascii 20)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (< (var-get total-chains) MAX-CHAINS) ERR-INVALID-CHAIN)
        (asserts! (is-none (map-get? chain-registry { chain-id: cid })) ERR-INVALID-CHAIN)
        
        (map-set chain-registry
            { chain-id: cid }
            {
                name: name,
                is-active: true,
                total-locked: u0,
                total-minted: u0
            }
        )
        (var-set total-chains (+ (var-get total-chains) u1))
        (ok cid)
    )
)

(define-public (add-validator (cid uint) (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain cid) ERR-INVALID-CHAIN)
        
        (map-set chain-validators
            { validator-chain-id: cid, validator: validator }
            { is-active: true }
        )
        (ok true)
    )
)

(define-public (lock-tokens (cid uint) (amount uint))
    (let
        (
            (current-locked (get-user-balance tx-sender cid "locked"))
            (current-balance (ft-get-balance bridge-token tx-sender))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain cid) ERR-INVALID-CHAIN)
        (asserts! (>= amount MIN-BRIDGE-AMOUNT) ERR-INVALID-AMOUNT)
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        (try! (ft-burn? bridge-token amount tx-sender))
        (update-user-balance tx-sender cid (+ current-locked amount) (get-user-balance tx-sender cid "wrapped"))
        (update-chain-totals cid (to-int amount) 0)
        (ok amount)
    )
)

(define-public (unlock-tokens (cid uint) (amount uint))
    (let
        (
            (current-locked (get-user-balance tx-sender cid "locked"))
            (withdrawal-id (var-get withdrawal-counter))
            (timelock-blocks (get-chain-timelock cid))
            (current-height stacks-block-height)
            (unlock-height (+ current-height timelock-blocks))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain cid) ERR-INVALID-CHAIN)
        (asserts! (>= current-locked amount) ERR-INSUFFICIENT-BALANCE)
        
        (update-user-balance tx-sender cid (- current-locked amount) (get-user-balance tx-sender cid "wrapped"))
        (update-chain-totals cid (- (to-int amount)) 0)
        
        (map-set withdrawal-queue
            { withdrawal-id: withdrawal-id }
            {
                user: tx-sender,
                target-chain-id: cid,
                amount: amount,
                requested-at: current-height,
                unlock-at: unlock-height,
                claimed: false
            }
        )
        
        (add-withdrawal-id-to-user tx-sender cid withdrawal-id)
        (var-set withdrawal-counter (+ withdrawal-id u1))
        (ok withdrawal-id)
    )
)

(define-public (mint-wrapped (cid uint) (amount uint) (recipient principal))
    (let
        (
            (current-wrapped (get-user-balance recipient cid "wrapped"))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain cid) ERR-INVALID-CHAIN)
        (asserts! (>= amount MIN-BRIDGE-AMOUNT) ERR-INVALID-AMOUNT)
        
        (update-user-balance recipient cid (get-user-balance recipient cid "locked") (+ current-wrapped amount))
        (update-chain-totals cid 0 (to-int amount))
        (ok amount)
    )
)

(define-public (burn-wrapped (cid uint) (amount uint))
    (let
        (
            (current-wrapped (get-user-balance tx-sender cid "wrapped"))
        )
        (asserts! (var-get is-bridge-active) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain cid) ERR-INVALID-CHAIN)
        (asserts! (>= current-wrapped amount) ERR-INSUFFICIENT-BALANCE)
        
        (update-user-balance tx-sender cid (get-user-balance tx-sender cid "locked") (- current-wrapped amount))
        (update-chain-totals cid 0 (- (to-int amount)))
        (ok amount)
    )
)

(define-public (bridge-transfer (from-chain uint) (to-chain uint) (amount uint) (recipient principal))
    (let
        (
            (current-height stacks-block-height)
            (tx-id (keccak256 (concat (concat (unwrap-panic (to-consensus-buff? tx-sender)) (unwrap-panic (to-consensus-buff? current-height))) (unwrap-panic (to-consensus-buff? amount)))))
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
                block-height: current-height
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

(define-public (claim-withdrawal (withdrawal-id uint))
    (let
        (
            (withdrawal-info (unwrap! (map-get? withdrawal-queue { withdrawal-id: withdrawal-id }) ERR-WITHDRAWAL-NOT-FOUND))
            (withdrawal-user (get user withdrawal-info))
            (withdrawal-amount (get amount withdrawal-info))
            (unlock-height (get unlock-at withdrawal-info))
            (is-claimed (get claimed withdrawal-info))
            (current-height stacks-block-height)
        )
        (asserts! (is-eq tx-sender withdrawal-user) ERR-NOT-AUTHORIZED)
        (asserts! (>= current-height unlock-height) ERR-WITHDRAWAL-LOCKED)
        (asserts! (not is-claimed) ERR-WITHDRAWAL-ALREADY-CLAIMED)
        
        (try! (ft-mint? bridge-token withdrawal-amount tx-sender))
        
        (map-set withdrawal-queue
            { withdrawal-id: withdrawal-id }
            (merge withdrawal-info { claimed: true })
        )
        
        (ok withdrawal-amount)
    )
)

(define-public (set-chain-timelock (cid uint) (timelock-blocks uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-chain cid) ERR-INVALID-CHAIN)
        
        (map-set chain-timelocks
            { timelock-chain-id: cid }
            { timelock-blocks: timelock-blocks }
        )
        (ok timelock-blocks)
    )
)

(define-public (cancel-withdrawal (withdrawal-id uint))
    (let
        (
            (withdrawal-info (unwrap! (map-get? withdrawal-queue { withdrawal-id: withdrawal-id }) ERR-WITHDRAWAL-NOT-FOUND))
            (withdrawal-user (get user withdrawal-info))
            (withdrawal-chain (get target-chain-id withdrawal-info))
            (withdrawal-amount (get amount withdrawal-info))
            (is-claimed (get claimed withdrawal-info))
            (current-locked (get-user-balance tx-sender withdrawal-chain "locked"))
        )
        (asserts! (is-eq tx-sender withdrawal-user) ERR-NOT-AUTHORIZED)
        (asserts! (not is-claimed) ERR-WITHDRAWAL-ALREADY-CLAIMED)
        
        (update-user-balance tx-sender withdrawal-chain (+ current-locked withdrawal-amount) (get-user-balance tx-sender withdrawal-chain "wrapped"))
        (update-chain-totals withdrawal-chain (to-int withdrawal-amount) 0)
        
        (map-set withdrawal-queue
            { withdrawal-id: withdrawal-id }
            (merge withdrawal-info { claimed: true })
        )
        
        (ok withdrawal-amount)
    )
)

(define-read-only (get-chain-info (cid uint))
    (map-get? chain-registry { chain-id: cid })
)

(define-read-only (get-user-chain-balance (user principal) (cid uint))
    (map-get? user-balances { user: user, balance-chain-id: cid })
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

(define-read-only (is-validator (cid uint) (validator principal))
    (match (map-get? chain-validators { validator-chain-id: cid, validator: validator })
        validator-info (get is-active validator-info)
        false
    )
)

(define-read-only (get-withdrawal-info (withdrawal-id uint))
    (map-get? withdrawal-queue { withdrawal-id: withdrawal-id })
)

(define-read-only (get-user-withdrawals (user principal) (cid uint))
    (map-get? user-withdrawal-ids { user: user, user-chain-id: cid })
)

(define-read-only (get-chain-timelock-info (cid uint))
    (ok (get-chain-timelock cid))
)

(define-read-only (get-withdrawal-counter)
    (var-get withdrawal-counter)
)

(define-public (approve (spender principal) (amount uint))
    (begin
        (map-set allowances { owner: tx-sender, spender: spender } { amount: amount })
        (ok amount)
    )
)

(define-public (revoke-allowance (spender principal))
    (begin
        (map-set allowances { owner: tx-sender, spender: spender } { amount: u0 })
        (ok true)
    )
)

(define-public (spend-from (owner principal) (recipient principal) (amount uint))
    (let
        (
            (current-allowance (match (map-get? allowances { owner: owner, spender: tx-sender }) info (get amount info) u0))
            (owner-balance (ft-get-balance bridge-token owner))
        )
        (asserts! (> current-allowance u0) ERR-NOT-AUTHORIZED)
        (asserts! (>= current-allowance amount) ERR-ALLOWANCE-INSUFFICIENT)
        (asserts! (>= owner-balance amount) ERR-INSUFFICIENT-BALANCE)
        (try! (ft-transfer? bridge-token amount owner recipient))
        (map-set allowances { owner: owner, spender: tx-sender } { amount: (- current-allowance amount) })
        (ok amount)
    )
)

(define-read-only (get-allowance (owner principal) (spender principal))
    (match (map-get? allowances { owner: owner, spender: spender })
        info (get amount info)
        u0
    )
)
