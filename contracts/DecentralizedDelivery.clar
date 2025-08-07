;; DecentralizedDelivery - Last Mile Delivery Platform
;; Core features: Service areas, delivery management, payments

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-stake (err u104))


(define-map EscrowHoldings
    uint
    {
        amount: uint,
        customer: principal,
        courier: (optional principal),
        locked: bool,
        created-at: uint,
        expires-at: uint
    }
)

(define-map EscrowBalances
    principal
    uint
)

(define-constant ESCROW_TIMEOUT u1008)
(define-constant err-escrow-locked (err u105))
(define-constant err-escrow-expired (err u106))
(define-constant err-insufficient-balance (err u107))


;; Data Variables
(define-data-var min-stake-amount uint u1000)
(define-data-var delivery-counter uint u0)

;; Delivery Status Types
(define-constant STATUS_PENDING u1)
(define-constant STATUS_ASSIGNED u2)
(define-constant STATUS_IN_TRANSIT u3)
(define-constant STATUS_DELIVERED u4)
(define-constant STATUS_CANCELLED u5)

;; Data Maps
(define-map DeliveryJobs
    uint 
    {
        customer: principal,
        courier: (optional principal),
        pickup-location: (string-ascii 50),
        delivery-location: (string-ascii 50),
        payment-amount: uint,
        status: uint,
        timestamp: uint
    }
)

(define-map CourierStakes
    principal
    {
        staked-amount: uint,
        service-area: (string-ascii 50),
        active: bool,
        reputation-score: uint,
        total-deliveries: uint
    }
)

(define-map ServiceAreas
    (string-ascii 50)
    {
        min-stake: uint,
        active-couriers: uint
    }
)

;; Public Functions

;; Stake tokens to become a courier
(define-public (stake-courier (amount uint) (service-area (string-ascii 50)))
    (let
        (
            (current-stake (default-to 
                { staked-amount: u0, service-area: "", active: false, reputation-score: u100, total-deliveries: u0 }
                (map-get? CourierStakes tx-sender)
            ))
        )
        (asserts! (>= amount (var-get min-stake-amount)) err-insufficient-stake)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (ok (map-set CourierStakes tx-sender
            {
                staked-amount: amount,
                service-area: service-area,
                active: true,
                reputation-score: u100,
                total-deliveries: u0
            }
        ))
    )
)

;; Create new delivery job
(define-public (create-delivery-job (pickup (string-ascii 50)) (delivery (string-ascii 50)) (payment uint))
    (let
        ((job-id (+ (var-get delivery-counter) u1)))
        (map-set DeliveryJobs job-id
            {
                customer: tx-sender,
                courier: none,
                pickup-location: pickup,
                delivery-location: delivery,
                payment-amount: payment,
                status: STATUS_PENDING,
                timestamp: stacks-block-height
            }
        )
        (var-set delivery-counter job-id)
        (ok job-id)
    )
)

;; Accept delivery job
(define-public (accept-delivery (job-id uint))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (courier-stake (unwrap! (map-get? CourierStakes tx-sender) err-unauthorized))
        )
        (asserts! (is-eq (get status job) STATUS_PENDING) err-invalid-status)
        (asserts! (get active courier-stake) err-unauthorized)
        (ok (map-set DeliveryJobs job-id
            (merge job {
                courier: (some tx-sender),
                status: STATUS_ASSIGNED
            })
        ))
    )
)

;; Update delivery status
(define-public (update-delivery-status (job-id uint) (new-status uint))
    (let
        ((job (unwrap! (map-get? DeliveryJobs job-id) err-not-found)))
        (asserts! (is-eq (some tx-sender) (get courier job)) err-unauthorized)
        (asserts! (< (get status job) new-status) err-invalid-status)
        (ok (map-set DeliveryJobs job-id
            (merge job {
                status: new-status
            })
        ))
    )
)

;; Complete delivery and process payment
(define-public (complete-delivery (job-id uint))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (courier (unwrap! (get courier job) err-unauthorized))
            (courier-stake (unwrap! (map-get? CourierStakes courier) err-not-found))
        )
        (asserts! (is-eq courier tx-sender) err-unauthorized)
        (asserts! (is-eq (get status job) STATUS_IN_TRANSIT) err-invalid-status)
        
        ;; Process payment
        (try! (stx-transfer? (get payment-amount job) (get customer job) courier))
        
        ;; Update courier stats
        (map-set CourierStakes courier
            (merge courier-stake {
                total-deliveries: (+ (get total-deliveries courier-stake) u1)
            })
        )
        
        ;; Update job status
        (ok (map-set DeliveryJobs job-id
            (merge job {
                status: STATUS_DELIVERED
            })
        ))
    )
)

;; Read-only functions

(define-read-only (get-delivery-job (job-id uint))
    (map-get? DeliveryJobs job-id)
)

(define-read-only (get-courier-info (courier principal))
    (map-get? CourierStakes courier)
)

(define-read-only (get-service-area (area (string-ascii 50)))
    (map-get? ServiceAreas area)
)

;; Admin functions

(define-public (set-min-stake (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (var-set min-stake-amount amount))
    )
)


(define-public (set-service-area (area (string-ascii 50)) (min-stake uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set ServiceAreas area
            {
                min-stake: min-stake,
                active-couriers: u0
            }
        ))
    )
)


(define-public (update-service-area (area (string-ascii 50)) (min-stake uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set ServiceAreas area
            {
                min-stake: min-stake,
                active-couriers: u0
            }
        ))
    )
)


(define-map UserRatings
    { rater: principal, rated: principal }
    { rating: uint, timestamp: uint }
)

(define-map AggregateRatings
    principal
    { total-rating: uint, rating-count: uint }
)

(define-constant MAX_RATING u5)

(define-public (submit-rating (rated-user principal) (rating uint))
    (let (
        (job-id (- (var-get delivery-counter) u1))
        (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
        (current-aggregate (default-to { total-rating: u0, rating-count: u0 } 
            (map-get? AggregateRatings rated-user)))
    )
        (asserts! (<= rating MAX_RATING) (err u200))
        (asserts! (or 
            (is-eq tx-sender (get customer job))
            (is-eq (some tx-sender) (get courier job))
        ) err-unauthorized)
        
        (map-set UserRatings { rater: tx-sender, rated: rated-user }
            { rating: rating, timestamp: stacks-block-height }
        )
        
        (ok (map-set AggregateRatings rated-user
            {
                total-rating: (+ (get total-rating current-aggregate) rating),
                rating-count: (+ (get rating-count current-aggregate) u1)
            }
        ))
    )
)


(define-public (get-user-rating (rated-user principal))
    (let (
        (aggregate (unwrap! (map-get? AggregateRatings rated-user) err-not-found))
    )
        (ok {
            average-rating: (/ (get total-rating aggregate) (get rating-count aggregate)),
            total-ratings: (get rating-count aggregate)
        })
    )
)


(define-map Disputes 
    uint 
    {
        job-id: uint,
        complainant: principal,
        defendant: principal,
        reason: (string-ascii 100),
        status: uint,
        timestamp: uint
    }
)

(define-data-var dispute-counter uint u0)
(define-constant DISPUTE_OPEN u1)
(define-constant DISPUTE_RESOLVED u2)

(define-public (file-dispute (job-id uint) (reason (string-ascii 100)))
    (let (
        (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
        (dispute-id (+ (var-get dispute-counter) u1))
    )
        (asserts! (or 
            (is-eq tx-sender (get customer job))
            (is-eq (some tx-sender) (get courier job))
        ) err-unauthorized)
        
        (var-set dispute-counter dispute-id)
        (ok (map-set Disputes dispute-id
            {
                job-id: job-id,
                complainant: tx-sender,
                defendant: (if (is-eq tx-sender (get customer job))
                    (unwrap! (get courier job) err-not-found)
                    (get customer job)),
                reason: reason,
                status: DISPUTE_OPEN,
                timestamp: stacks-block-height
            }
        ))
    )
)


(define-public (resolve-dispute (dispute-id uint) (resolution uint))
    (let (
        (dispute (unwrap! (map-get? Disputes dispute-id) err-not-found))
    )
        (asserts! (is-eq tx-sender (get complainant dispute)) err-unauthorized)
        (asserts! (is-eq (get status dispute) DISPUTE_OPEN) err-invalid-status)
        
        ;; Update dispute status
        (ok (map-set Disputes dispute-id
            {
                job-id: (get job-id dispute),
                complainant: tx-sender,
                defendant: (get defendant dispute),
                reason: (get reason dispute),
                status: resolution,
                timestamp: stacks-block-height
            }
        ))
    )
)


(define-map SecurityDeposits
    uint
    {
        amount: uint,
        depositor: principal,
        refundable: bool
    }
)

(define-constant SECURITY_DEPOSIT_AMOUNT u500)

(define-public (add-security-deposit (job-id uint))
    (let (
        (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
    )
        (asserts! (is-eq tx-sender (get customer job)) err-unauthorized)
        (try! (stx-transfer? SECURITY_DEPOSIT_AMOUNT tx-sender (as-contract tx-sender)))
        
        (ok (map-set SecurityDeposits job-id
            {
                amount: SECURITY_DEPOSIT_AMOUNT,
                depositor: tx-sender,
                refundable: true
            }
        ))
    )
)

(define-public (refund-security-deposit (job-id uint))
    (let (
        (deposit (unwrap! (map-get? SecurityDeposits job-id) err-not-found))
        (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
    )
        (asserts! (is-eq (get status job) STATUS_DELIVERED) err-invalid-status)
        (asserts! (get refundable deposit) err-unauthorized)
        (try! (as-contract (stx-transfer? (get amount deposit) tx-sender (get depositor deposit))))
        
        (ok (map-set SecurityDeposits job-id
            (merge deposit { refundable: false })
        ))
    )
)

(define-map DeliveryIncentives
    uint
    {
        base-amount: uint,
        bonus-amount: uint,
        deadline: uint,
        claimed: bool
    }
)

(define-constant BONUS_PERCENTAGE u10)

(define-public (set-delivery-incentive (job-id uint) (deadline uint))
    (let (
        (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
        (bonus (/ (* (get payment-amount job) BONUS_PERCENTAGE) u100))
    )
        (asserts! (is-eq tx-sender (get customer job)) err-unauthorized)
        
        (ok (map-set DeliveryIncentives job-id
            {
                base-amount: (get payment-amount job),
                bonus-amount: bonus,
                deadline: deadline,
                claimed: false
            }
        ))
    )
)

(define-public (claim-time-bonus (job-id uint))
    (let (
        (incentive (unwrap! (map-get? DeliveryIncentives job-id) err-not-found))
        (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
    )
        (asserts! (is-eq (some tx-sender) (get courier job)) err-unauthorized)
        (asserts! (is-eq (get status job) STATUS_DELIVERED) err-invalid-status)
        (asserts! (< stacks-block-height (get deadline incentive)) err-unauthorized)
        (asserts! (not (get claimed incentive)) err-unauthorized)
        
        (try! (as-contract (stx-transfer? (get bonus-amount incentive) tx-sender tx-sender)))
        
        (ok (map-set DeliveryIncentives job-id
            (merge incentive { claimed: true })
        ))
    )
)


(define-map CourierSpecialization
    { courier: principal, service-type: (string-ascii 20) }
    { certified: bool, experience-points: uint }
)

(define-constant SERVICE_TYPE_FOOD "food")
(define-constant SERVICE_TYPE_MEDICAL "medical")
(define-constant SERVICE_TYPE_EXPRESS "express")

(define-public (register-specialization (service-type (string-ascii 20)))
    (let (
        (courier-stake (unwrap! (map-get? CourierStakes tx-sender) err-unauthorized))
    )
        (asserts! (get active courier-stake) err-unauthorized)
        
        (ok (map-set CourierSpecialization { courier: tx-sender, service-type: service-type }
            {
                certified: false,
                experience-points: u0
            }
        ))
    )
)

(define-public (add-experience-points (courier principal) (service-type (string-ascii 20)) (points uint))
    (let (
        (spec (unwrap! (map-get? CourierSpecialization { courier: courier, service-type: service-type }) err-not-found))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (ok (map-set CourierSpecialization { courier: courier, service-type: service-type }
            (merge spec { experience-points: (+ (get experience-points spec) points) })
        ))
    )
)





(define-map InsurancePool
    principal
    {
        insured-amount: uint,
        coverage-expiry: uint,
        claims-made: uint
    }
)

(define-constant INSURANCE_PERIOD u52560)
(define-constant MIN_INSURANCE_AMOUNT u1000)

(define-public (join-insurance-pool (amount uint))
    (let (
        (current-insurance (default-to 
            { insured-amount: u0, coverage-expiry: u0, claims-made: u0 }
            (map-get? InsurancePool tx-sender)
        ))
    )
        (asserts! (>= amount MIN_INSURANCE_AMOUNT) err-insufficient-stake)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (ok (map-set InsurancePool tx-sender
            {
                insured-amount: amount,
                coverage-expiry: (+ stacks-block-height INSURANCE_PERIOD),
                claims-made: u0
            }
        ))
    )
)

(define-public (claim-insurance (job-id uint) (claim-amount uint))
    (let (
        (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
        (insurance (unwrap! (map-get? InsurancePool tx-sender) err-not-found))
    )
        (asserts! (is-eq (some tx-sender) (get courier job)) err-unauthorized)
        (asserts! (<= claim-amount (get insured-amount insurance)) err-unauthorized)
        (asserts! (< stacks-block-height (get coverage-expiry insurance)) err-unauthorized)
        
        (try! (as-contract (stx-transfer? claim-amount tx-sender tx-sender)))
        
        (ok (map-set InsurancePool tx-sender
            (merge insurance 
                { claims-made: (+ (get claims-made insurance) u1) }
            )
        ))
    )
)


(define-map DemandMetrics
    (string-ascii 50)
    {
        active-jobs: uint,
        base-price-multiplier: uint,
        last-updated: uint
    }
)

(define-constant MAX_MULTIPLIER u300)
(define-constant MIN_MULTIPLIER u100)
(define-constant UPDATE_INTERVAL u144)

(define-public (update-demand-metrics (area (string-ascii 50)))
    (let (
        (current-metrics (default-to 
            { active-jobs: u0, base-price-multiplier: u100, last-updated: u0 }
            (map-get? DemandMetrics area)
        ))
        (service-area (unwrap! (map-get? ServiceAreas area) err-not-found))
    )
        (asserts! (>= (- stacks-block-height (get last-updated current-metrics)) UPDATE_INTERVAL) err-unauthorized)
        
        (ok (map-set DemandMetrics area
            {
                active-jobs: (var-get delivery-counter),
                base-price-multiplier: (calculate-multiplier 
                    (get active-couriers service-area)
                    (var-get delivery-counter)
                ),
                last-updated: stacks-block-height
            }
        ))
    )
)

(define-private (min-uint (a uint) (b uint))
    (if (<= a b) a b))

(define-private (max-uint (a uint) (b uint))
    (if (>= a b) a b))

(define-private (calculate-multiplier (couriers uint) (jobs uint))
    (if (is-eq couriers u0)
        MAX_MULTIPLIER
        (min-uint MAX_MULTIPLIER 
            (max-uint MIN_MULTIPLIER 
                (* u100 (/ jobs couriers))
            )
        )
    )
)



(define-public (create-delivery-job-with-escrow (pickup (string-ascii 50)) (delivery (string-ascii 50)) (payment uint))
    (let
        (
            (job-id (+ (var-get delivery-counter) u1))
            (customer-balance (default-to u0 (map-get? EscrowBalances tx-sender)))
        )
        (asserts! (>= customer-balance payment) err-insufficient-balance)
        
        (map-set EscrowHoldings job-id
            {
                amount: payment,
                customer: tx-sender,
                courier: none,
                locked: true,
                created-at: stacks-block-height,
                expires-at: (+ stacks-block-height ESCROW_TIMEOUT)
            }
        )
        
        (map-set EscrowBalances tx-sender (- customer-balance payment))
        
        (map-set DeliveryJobs job-id
            {
                customer: tx-sender,
                courier: none,
                pickup-location: pickup,
                delivery-location: delivery,
                payment-amount: payment,
                status: STATUS_PENDING,
                timestamp: stacks-block-height
            }
        )
        
        (var-set delivery-counter job-id)
        (ok job-id)
    )
)

(define-public (deposit-to-escrow (amount uint))
    (let
        ((current-balance (default-to u0 (map-get? EscrowBalances tx-sender))))
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (ok (map-set EscrowBalances tx-sender (+ current-balance amount)))
    )
)

(define-public (complete-delivery-with-escrow (job-id uint))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (escrow (unwrap! (map-get? EscrowHoldings job-id) err-not-found))
            (courier (unwrap! (get courier job) err-unauthorized))
            (courier-stake (unwrap! (map-get? CourierStakes courier) err-not-found))
        )
        (asserts! (is-eq courier tx-sender) err-unauthorized)
        (asserts! (is-eq (get status job) STATUS_IN_TRANSIT) err-invalid-status)
        (asserts! (get locked escrow) err-escrow-locked)
        
        (try! (as-contract (stx-transfer? (get amount escrow) tx-sender courier)))
        
        (map-set EscrowHoldings job-id
            (merge escrow { locked: false })
        )
        
        (map-set CourierStakes courier
            (merge courier-stake {
                total-deliveries: (+ (get total-deliveries courier-stake) u1)
            })
        )
        
        (ok (map-set DeliveryJobs job-id
            (merge job { status: STATUS_DELIVERED })
        ))
    )
)

(define-public (cancel-delivery-with-refund (job-id uint))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (escrow (unwrap! (map-get? EscrowHoldings job-id) err-not-found))
            (customer-balance (default-to u0 (map-get? EscrowBalances (get customer escrow))))
        )
        (asserts! (is-eq tx-sender (get customer job)) err-unauthorized)
        (asserts! (is-eq (get status job) STATUS_PENDING) err-invalid-status)
        (asserts! (get locked escrow) err-escrow-locked)
        
        (map-set EscrowBalances (get customer escrow) 
            (+ customer-balance (get amount escrow))
        )
        
        (map-set EscrowHoldings job-id
            (merge escrow { locked: false })
        )
        
        (ok (map-set DeliveryJobs job-id
            (merge job { status: STATUS_CANCELLED })
        ))
    )
)

(define-public (withdraw-from-escrow (amount uint))
    (let
        ((current-balance (default-to u0 (map-get? EscrowBalances tx-sender))))
        (asserts! (>= current-balance amount) err-insufficient-balance)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (ok (map-set EscrowBalances tx-sender (- current-balance amount)))
    )
)

(define-public (claim-expired-escrow (job-id uint))
    (let
        (
            (escrow (unwrap! (map-get? EscrowHoldings job-id) err-not-found))
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (customer-balance (default-to u0 (map-get? EscrowBalances (get customer escrow))))
        )
        (asserts! (> stacks-block-height (get expires-at escrow)) err-escrow-expired)
        (asserts! (get locked escrow) err-escrow-locked)
        (asserts! (not (is-eq (get status job) STATUS_DELIVERED)) err-invalid-status)
        
        (map-set EscrowBalances (get customer escrow) 
            (+ customer-balance (get amount escrow))
        )
        
        (map-set EscrowHoldings job-id
            (merge escrow { locked: false })
        )
        
        (ok (map-set DeliveryJobs job-id
            (merge job { status: STATUS_CANCELLED })
        ))
    )
)

(define-read-only (get-escrow-balance (user principal))
    (default-to u0 (map-get? EscrowBalances user))
)

(define-read-only (get-escrow-holding (job-id uint))
    (map-get? EscrowHoldings job-id)
)

(define-map DeliverySignatures
    uint
    {
        customer-signed: bool,
        courier-signed: bool,
        third-party-signed: bool,
        third-party-validator: (optional principal),
        signatures-required: uint,
        signatures-collected: uint,
        completion-timestamp: uint
    }
)

(define-constant SIGNATURE_CUSTOMER u1)
(define-constant SIGNATURE_COURIER u2)
(define-constant SIGNATURE_THIRD_PARTY u3)
(define-constant MIN_SIGNATURES_DEFAULT u2)
(define-constant MIN_SIGNATURES_HIGH_VALUE u3)
(define-constant HIGH_VALUE_THRESHOLD u5000)

(define-public (initialize-delivery-signatures (job-id uint) (third-party-validator (optional principal)))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (required-signatures (if (>= (get payment-amount job) HIGH_VALUE_THRESHOLD)
                MIN_SIGNATURES_HIGH_VALUE
                MIN_SIGNATURES_DEFAULT))
        )
        (asserts! (is-eq tx-sender (get customer job)) err-unauthorized)
        (asserts! (is-eq (get status job) STATUS_PENDING) err-invalid-status)
        
        (ok (map-set DeliverySignatures job-id
            {
                customer-signed: false,
                courier-signed: false,
                third-party-signed: false,
                third-party-validator: third-party-validator,
                signatures-required: required-signatures,
                signatures-collected: u0,
                completion-timestamp: u0
            }
        ))
    )
)

(define-public (sign-delivery-completion (job-id uint) (signature-type uint))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (signatures (unwrap! (map-get? DeliverySignatures job-id) err-not-found))
        )
        (asserts! (is-eq (get status job) STATUS_IN_TRANSIT) err-invalid-status)
        
        (if (is-eq signature-type SIGNATURE_CUSTOMER)
            (begin
                (asserts! (is-eq tx-sender (get customer job)) err-unauthorized)
                (asserts! (not (get customer-signed signatures)) err-unauthorized)
                (ok (map-set DeliverySignatures job-id
                    (merge signatures {
                        customer-signed: true,
                        signatures-collected: (+ (get signatures-collected signatures) u1)
                    })
                ))
            )
            (if (is-eq signature-type SIGNATURE_COURIER)
                (begin
                    (asserts! (is-eq (some tx-sender) (get courier job)) err-unauthorized)
                    (asserts! (not (get courier-signed signatures)) err-unauthorized)
                    (ok (map-set DeliverySignatures job-id
                        (merge signatures {
                            courier-signed: true,
                            signatures-collected: (+ (get signatures-collected signatures) u1)
                        })
                    ))
                )
                (if (is-eq signature-type SIGNATURE_THIRD_PARTY)
                    (begin
                        (asserts! (is-eq (some tx-sender) (get third-party-validator signatures)) err-unauthorized)
                        (asserts! (not (get third-party-signed signatures)) err-unauthorized)
                        (ok (map-set DeliverySignatures job-id
                            (merge signatures {
                                third-party-signed: true,
                                signatures-collected: (+ (get signatures-collected signatures) u1)
                            })
                        ))
                    )
                    err-invalid-status
                )
            )
        )
    )
)

(define-public (complete-delivery-with-signatures (job-id uint))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (signatures (unwrap! (map-get? DeliverySignatures job-id) err-not-found))
            (courier (unwrap! (get courier job) err-unauthorized))
            (courier-stake (unwrap! (map-get? CourierStakes courier) err-not-found))
        )
        (asserts! (is-eq (get status job) STATUS_IN_TRANSIT) err-invalid-status)
        (asserts! (>= (get signatures-collected signatures) (get signatures-required signatures)) err-unauthorized)
        (asserts! (get customer-signed signatures) err-unauthorized)
        (asserts! (get courier-signed signatures) err-unauthorized)
        
        (if (is-eq (get signatures-required signatures) MIN_SIGNATURES_HIGH_VALUE)
            (asserts! (get third-party-signed signatures) err-unauthorized)
            true
        )
        
        (try! (stx-transfer? (get payment-amount job) (get customer job) courier))
        
        (map-set DeliverySignatures job-id
            (merge signatures { completion-timestamp: stacks-block-height })
        )
        
        (map-set CourierStakes courier
            (merge courier-stake {
                total-deliveries: (+ (get total-deliveries courier-stake) u1)
            })
        )
        
        (ok (map-set DeliveryJobs job-id
            (merge job { status: STATUS_DELIVERED })
        ))
    )
)

(define-public (complete-delivery-with-escrow-signatures (job-id uint))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (escrow (unwrap! (map-get? EscrowHoldings job-id) err-not-found))
            (signatures (unwrap! (map-get? DeliverySignatures job-id) err-not-found))
            (courier (unwrap! (get courier job) err-unauthorized))
            (courier-stake (unwrap! (map-get? CourierStakes courier) err-not-found))
        )
        (asserts! (is-eq (get status job) STATUS_IN_TRANSIT) err-invalid-status)
        (asserts! (get locked escrow) err-escrow-locked)
        (asserts! (>= (get signatures-collected signatures) (get signatures-required signatures)) err-unauthorized)
        (asserts! (get customer-signed signatures) err-unauthorized)
        (asserts! (get courier-signed signatures) err-unauthorized)
        
        (if (is-eq (get signatures-required signatures) MIN_SIGNATURES_HIGH_VALUE)
            (asserts! (get third-party-signed signatures) err-unauthorized)
            true
        )
        
        (try! (as-contract (stx-transfer? (get amount escrow) tx-sender courier)))
        
        (map-set EscrowHoldings job-id
            (merge escrow { locked: false })
        )
        
        (map-set DeliverySignatures job-id
            (merge signatures { completion-timestamp: stacks-block-height })
        )
        
        (map-set CourierStakes courier
            (merge courier-stake {
                total-deliveries: (+ (get total-deliveries courier-stake) u1)
            })
        )
        
        (ok (map-set DeliveryJobs job-id
            (merge job { status: STATUS_DELIVERED })
        ))
    )
)

(define-read-only (get-delivery-signatures (job-id uint))
    (map-get? DeliverySignatures job-id)
)

(define-read-only (is-delivery-ready-for-completion (job-id uint))
    (match (map-get? DeliverySignatures job-id)
        signatures (ok (>= (get signatures-collected signatures) (get signatures-required signatures)))
        err-not-found
    )
)

;; Package Tracking and Proof-of-Delivery System
;; Provides real-time tracking with immutable proof records

(define-map PackageTrackingData
    uint ;; job-id
    {
        package-weight: uint,
        package-dimensions: (string-ascii 30), ;; "LxWxH in cm"
        special-instructions: (string-ascii 100),
        fragile-item: bool,
        temperature-sensitive: bool,
        tracking-active: bool,
        pickup-verified: bool,
        delivery-verified: bool
    }
)

(define-map TrackingEvents
    { job-id: uint, event-id: uint }
    {
        event-type: uint,
        timestamp: uint,
        location-coords: (string-ascii 50), ;; "lat,lng"
        location-description: (string-ascii 50),
        courier: principal,
        photo-hash: (optional (string-ascii 64)), ;; IPFS hash or similar
        notes: (string-ascii 100),
        verified: bool
    }
)

(define-map TrackingCounters
    uint ;; job-id
    uint ;; event-counter
)

(define-map DeliveryProofs
    uint ;; job-id
    {
        pickup-photo-hash: (optional (string-ascii 64)),
        delivery-photo-hash: (optional (string-ascii 64)),
        recipient-signature-hash: (optional (string-ascii 64)),
        package-condition-rating: uint, ;; 1-5 scale
        delivery-confirmation-code: (string-ascii 10),
        proof-timestamp: uint,
        witness-address: (optional principal)
    }
)

;; Event type constants
(define-constant EVENT_PICKUP_INITIATED u1)
(define-constant EVENT_PICKUP_COMPLETED u2)
(define-constant EVENT_IN_TRANSIT u3)
(define-constant EVENT_DELIVERY_ATTEMPTED u4)
(define-constant EVENT_DELIVERY_COMPLETED u5)
(define-constant EVENT_EXCEPTION_OCCURRED u6)

;; Error constants for tracking
(define-constant err-tracking-not-active (err u300))
(define-constant err-invalid-event-type (err u301))
(define-constant err-proof-already-submitted (err u302))
(define-constant err-invalid-condition-rating (err u303))

;; Initialize package tracking for a delivery job
(define-public (initialize-package-tracking 
    (job-id uint) 
    (weight uint) 
    (dimensions (string-ascii 30))
    (special-instructions (string-ascii 100))
    (fragile bool)
    (temp-sensitive bool))
    (let
        ((job (unwrap! (map-get? DeliveryJobs job-id) err-not-found)))
        ;; Only customer can initialize tracking
        (asserts! (is-eq tx-sender (get customer job)) err-unauthorized)
        (asserts! (is-eq (get status job) STATUS_PENDING) err-invalid-status)
        
        ;; Set initial tracking data
        (map-set PackageTrackingData job-id
            {
                package-weight: weight,
                package-dimensions: dimensions,
                special-instructions: special-instructions,
                fragile-item: fragile,
                temperature-sensitive: temp-sensitive,
                tracking-active: true,
                pickup-verified: false,
                delivery-verified: false
            }
        )
        
        ;; Initialize event counter
        (map-set TrackingCounters job-id u0)
        
        (ok true)
    )
)

;; Record a tracking event during delivery
(define-public (record-tracking-event
    (job-id uint)
    (event-type uint)
    (location-coords (string-ascii 50))
    (location-desc (string-ascii 50))
    (photo-hash (optional (string-ascii 64)))
    (notes (string-ascii 100)))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (tracking-data (unwrap! (map-get? PackageTrackingData job-id) err-not-found))
            (current-counter (default-to u0 (map-get? TrackingCounters job-id)))
            (new-event-id (+ current-counter u1))
        )
        ;; Only assigned courier can record events
        (asserts! (is-eq (some tx-sender) (get courier job)) err-unauthorized)
        (asserts! (get tracking-active tracking-data) err-tracking-not-active)
        (asserts! (and (>= event-type u1) (<= event-type u6)) err-invalid-event-type)
        
        ;; Record the tracking event
        (map-set TrackingEvents { job-id: job-id, event-id: new-event-id }
            {
                event-type: event-type,
                timestamp: stacks-block-height,
                location-coords: location-coords,
                location-description: location-desc,
                courier: tx-sender,
                photo-hash: photo-hash,
                notes: notes,
                verified: true
            }
        )
        
        ;; Update event counter
        (map-set TrackingCounters job-id new-event-id)
        
        ;; Update pickup/delivery verification status
        (if (is-eq event-type EVENT_PICKUP_COMPLETED)
            (map-set PackageTrackingData job-id
                (merge tracking-data { pickup-verified: true }))
            (if (is-eq event-type EVENT_DELIVERY_COMPLETED)
                (map-set PackageTrackingData job-id
                    (merge tracking-data { delivery-verified: true }))
                true
            )
        )
        
        (ok new-event-id)
    )
)

;; Submit proof of delivery with photos and signature
(define-public (submit-delivery-proof
    (job-id uint)
    (pickup-photo (optional (string-ascii 64)))
    (delivery-photo (optional (string-ascii 64)))
    (signature-hash (optional (string-ascii 64)))
    (condition-rating uint)
    (confirmation-code (string-ascii 10))
    (witness (optional principal)))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (tracking-data (unwrap! (map-get? PackageTrackingData job-id) err-not-found))
        )
        ;; Only courier can submit delivery proof
        (asserts! (is-eq (some tx-sender) (get courier job)) err-unauthorized)
        (asserts! (is-eq (get status job) STATUS_IN_TRANSIT) err-invalid-status)
        (asserts! (get tracking-active tracking-data) err-tracking-not-active)
        (asserts! (and (>= condition-rating u1) (<= condition-rating u5)) err-invalid-condition-rating)
        
        ;; Ensure proof hasn't been submitted already
        (asserts! (is-none (map-get? DeliveryProofs job-id)) err-proof-already-submitted)
        
        ;; Store delivery proof
        (map-set DeliveryProofs job-id
            {
                pickup-photo-hash: pickup-photo,
                delivery-photo-hash: delivery-photo,
                recipient-signature-hash: signature-hash,
                package-condition-rating: condition-rating,
                delivery-confirmation-code: confirmation-code,
                proof-timestamp: stacks-block-height,
                witness-address: witness
            }
        )
        
        (ok true)
    )
)

;; Verify delivery proof by customer
(define-public (verify-delivery-proof (job-id uint) (confirmation-code (string-ascii 10)))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (proof (unwrap! (map-get? DeliveryProofs job-id) err-not-found))
            (tracking-data (unwrap! (map-get? PackageTrackingData job-id) err-not-found))
        )
        ;; Only customer can verify proof
        (asserts! (is-eq tx-sender (get customer job)) err-unauthorized)
        (asserts! (is-eq (get delivery-confirmation-code proof) confirmation-code) err-unauthorized)
        
        ;; Mark delivery as verified
        (map-set PackageTrackingData job-id
            (merge tracking-data { 
                delivery-verified: true,
                tracking-active: false
            })
        )
        
        (ok true)
    )
)

;; Report package exception or issue
(define-public (report-package-exception
    (job-id uint)
    (exception-type (string-ascii 50))
    (description (string-ascii 100))
    (photo-evidence (optional (string-ascii 64))))
    (let
        (
            (job (unwrap! (map-get? DeliveryJobs job-id) err-not-found))
            (tracking-data (unwrap! (map-get? PackageTrackingData job-id) err-not-found))
            (current-counter (default-to u0 (map-get? TrackingCounters job-id)))
            (new-event-id (+ current-counter u1))
        )
        ;; Either customer or courier can report exceptions
        (asserts! (or 
            (is-eq tx-sender (get customer job))
            (is-eq (some tx-sender) (get courier job))) err-unauthorized)
        (asserts! (get tracking-active tracking-data) err-tracking-not-active)
        
        ;; Record exception event
        (map-set TrackingEvents { job-id: job-id, event-id: new-event-id }
            {
                event-type: EVENT_EXCEPTION_OCCURRED,
                timestamp: stacks-block-height,
                location-coords: "Unknown",
                location-description: exception-type,
                courier: (default-to tx-sender (get courier job)),
                photo-hash: photo-evidence,
                notes: description,
                verified: false ;; Exceptions need manual verification
            }
        )
        
        ;; Update event counter
        (map-set TrackingCounters job-id new-event-id)
        
        (ok new-event-id)
    )
)

;; Read-only functions for tracking data

(define-read-only (get-package-tracking-data (job-id uint))
    (map-get? PackageTrackingData job-id)
)

(define-read-only (get-tracking-event (job-id uint) (event-id uint))
    (map-get? TrackingEvents { job-id: job-id, event-id: event-id })
)

(define-read-only (get-delivery-proof (job-id uint))
    (map-get? DeliveryProofs job-id)
)

(define-read-only (get-total-tracking-events (job-id uint))
    (default-to u0 (map-get? TrackingCounters job-id))
)

(define-read-only (is-package-tracking-active (job-id uint))
    (match (map-get? PackageTrackingData job-id)
        tracking-data (get tracking-active tracking-data)
        false
    )
)

(define-read-only (get-package-verification-status (job-id uint))
    (match (map-get? PackageTrackingData job-id)
        tracking-data (ok {
            pickup-verified: (get pickup-verified tracking-data),
            delivery-verified: (get delivery-verified tracking-data),
            tracking-active: (get tracking-active tracking-data)
        })
        err-not-found
    )
)
