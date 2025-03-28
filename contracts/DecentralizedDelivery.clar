;; DecentralizedDelivery - Last Mile Delivery Platform
;; Core features: Service areas, delivery management, payments

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-stake (err u104))

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