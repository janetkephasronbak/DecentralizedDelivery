;; Delivery Notifications - Real-time Notification Management System
;; Provides structured notification management for delivery events and user alerts

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u500))
(define-constant err-notification-not-found (err u501))
(define-constant err-invalid-notification-type (err u502))
(define-constant err-subscription-not-found (err u503))
(define-constant err-invalid-priority (err u504))

;; Notification type constants
(define-constant NOTIFICATION_JOB_CREATED u1)
(define-constant NOTIFICATION_JOB_ACCEPTED u2)
(define-constant NOTIFICATION_JOB_STARTED u3)
(define-constant NOTIFICATION_JOB_COMPLETED u4)
(define-constant NOTIFICATION_PAYMENT_RECEIVED u5)
(define-constant NOTIFICATION_RATING_RECEIVED u6)
(define-constant NOTIFICATION_DISPUTE_FILED u7)
(define-constant NOTIFICATION_BATCH_OPTIMIZED u8)

;; Priority levels
(define-constant PRIORITY_LOW u1)
(define-constant PRIORITY_NORMAL u2)
(define-constant PRIORITY_HIGH u3)
(define-constant PRIORITY_URGENT u4)

;; Data variables
(define-data-var notification-counter uint u0)

;; Notification storage
(define-map Notifications
    uint ;; notification-id
    {
        recipient: principal,
        sender: principal,
        notification-type: uint,
        title: (string-ascii 60),
        message: (string-ascii 150),
        job-id: (optional uint),
        batch-id: (optional uint),
        priority: uint,
        read: bool,
        created-at: uint,
        expires-at: uint
    }
)

;; User notification preferences
(define-map NotificationSettings
    principal
    {
        job-updates-enabled: bool,
        payment-notifications: bool,
        batch-notifications: bool,
        dispute-alerts: bool,
        email-notifications: bool,
        push-notifications: bool,
        max-notifications-per-day: uint
    }
)

;; Daily notification counters for users
(define-map DailyNotificationCounts
    { user: principal, day: uint }
    uint
)

;; User notification inboxes (last 20 notifications per user)
(define-map UserInboxes
    { user: principal, slot: uint }
    uint ;; notification-id
)

(define-map UserInboxCounters
    principal
    uint ;; current slot counter (0-19, circular)
)

;; Initialize notification settings for a user
(define-public (initialize-notification-settings 
    (job-updates bool)
    (payments bool)
    (batches bool)
    (disputes bool)
    (email bool)
    (push bool)
    (max-daily uint))
    (begin
        (map-set NotificationSettings tx-sender
            {
                job-updates-enabled: job-updates,
                payment-notifications: payments,
                batch-notifications: batches,
                dispute-alerts: disputes,
                email-notifications: email,
                push-notifications: push,
                max-notifications-per-day: max-daily
            }
        )
        (ok true)
    )
)

;; Send a notification to a user
(define-public (send-notification
    (recipient principal)
    (notification-type uint)
    (title (string-ascii 60))
    (message (string-ascii 150))
    (job-id (optional uint))
    (batch-id (optional uint))
    (priority uint))
    (let
        (
            (notification-id (+ (var-get notification-counter) u1))
            (current-day (/ stacks-block-height u144)) ;; Approximate day (144 blocks = 24h)
            (daily-count (default-to u0 
                (map-get? DailyNotificationCounts { user: recipient, day: current-day })))
            (user-settings (default-to
                {
                    job-updates-enabled: true,
                    payment-notifications: true,
                    batch-notifications: true,
                    dispute-alerts: true,
                    email-notifications: false,
                    push-notifications: true,
                    max-notifications-per-day: u50
                }
                (map-get? NotificationSettings recipient)
            ))
        )
        ;; Validate inputs
        (asserts! (and (>= notification-type u1) (<= notification-type u8)) err-invalid-notification-type)
        (asserts! (and (>= priority u1) (<= priority u4)) err-invalid-priority)
        
        ;; Check if user has reached daily limit
        (asserts! (< daily-count (get max-notifications-per-day user-settings)) err-not-authorized)
        
        ;; Check if notification type is enabled for user
        (asserts! (should-send-notification notification-type user-settings) err-not-authorized)
        
        ;; Create notification
        (map-set Notifications notification-id
            {
                recipient: recipient,
                sender: tx-sender,
                notification-type: notification-type,
                title: title,
                message: message,
                job-id: job-id,
                batch-id: batch-id,
                priority: priority,
                read: false,
                created-at: stacks-block-height,
                expires-at: (+ stacks-block-height u1440) ;; Expires in ~10 days
            }
        )
        
        ;; Update counters
        (var-set notification-counter notification-id)
        (map-set DailyNotificationCounts { user: recipient, day: current-day } (+ daily-count u1))
        
        ;; Add to user inbox (circular buffer of last 20 notifications)
        (let
            (
                (current-slot (default-to u0 (map-get? UserInboxCounters recipient)))
                (next-slot (mod (+ current-slot u1) u20))
            )
            (map-set UserInboxes { user: recipient, slot: current-slot } notification-id)
            (map-set UserInboxCounters recipient next-slot)
        )
        
        (ok notification-id)
    )
)

;; Mark notification as read
(define-public (mark-notification-read (notification-id uint))
    (let
        ((notification (unwrap! (map-get? Notifications notification-id) err-notification-not-found)))
        (asserts! (is-eq tx-sender (get recipient notification)) err-not-authorized)
        (ok (map-set Notifications notification-id
            (merge notification { read: true })
        ))
    )
)

;; Mark multiple notifications as read
(define-public (mark-multiple-read (notification-ids (list 10 uint)))
    (ok (map mark-single-read notification-ids))
)

;; Helper function to mark a single notification as read
(define-private (mark-single-read (notification-id uint))
    (match (map-get? Notifications notification-id)
        notification (if (is-eq tx-sender (get recipient notification))
            (begin
                (map-set Notifications notification-id (merge notification { read: true }))
                true
            )
            false
        )
        false
    )
)

;; Delete expired notifications (admin function)
(define-public (cleanup-expired-notifications (notification-ids (list 20 uint)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (ok (map delete-if-expired notification-ids))
    )
)

;; Helper function to delete expired notification
(define-private (delete-if-expired (notification-id uint))
    (match (map-get? Notifications notification-id)
        notification (if (> stacks-block-height (get expires-at notification))
            (begin
                (map-delete Notifications notification-id)
                true
            )
            false
        )
        false
    )
)

;; Helper function to check if notification should be sent based on user settings
(define-private (should-send-notification (notification-type uint) (settings (tuple (job-updates-enabled bool) (payment-notifications bool) (batch-notifications bool) (dispute-alerts bool) (email-notifications bool) (push-notifications bool) (max-notifications-per-day uint))))
    (if (or (is-eq notification-type NOTIFICATION_JOB_CREATED)
            (is-eq notification-type NOTIFICATION_JOB_ACCEPTED)
            (is-eq notification-type NOTIFICATION_JOB_STARTED)
            (is-eq notification-type NOTIFICATION_JOB_COMPLETED))
        (get job-updates-enabled settings)
        (if (is-eq notification-type NOTIFICATION_PAYMENT_RECEIVED)
            (get payment-notifications settings)
            (if (is-eq notification-type NOTIFICATION_BATCH_OPTIMIZED)
                (get batch-notifications settings)
                (if (is-eq notification-type NOTIFICATION_DISPUTE_FILED)
                    (get dispute-alerts settings)
                    true ;; Default to true for other types
                )
            )
        )
    )
)

;; Helper function to check if optional value exists
(define-private (is-some-helper (value (optional uint)))
    (is-some value)
)

;; Read-only functions

(define-read-only (get-notification (notification-id uint))
    (map-get? Notifications notification-id)
)

(define-read-only (get-user-notification-settings (user principal))
    (map-get? NotificationSettings user)
)

(define-read-only (get-user-inbox (user principal))
    (list
        (map-get? UserInboxes { user: user, slot: u0 })
        (map-get? UserInboxes { user: user, slot: u1 })
        (map-get? UserInboxes { user: user, slot: u2 })
        (map-get? UserInboxes { user: user, slot: u3 })
        (map-get? UserInboxes { user: user, slot: u4 })
        (map-get? UserInboxes { user: user, slot: u5 })
        (map-get? UserInboxes { user: user, slot: u6 })
        (map-get? UserInboxes { user: user, slot: u7 })
        (map-get? UserInboxes { user: user, slot: u8 })
        (map-get? UserInboxes { user: user, slot: u9 })
    )
)

(define-read-only (get-unread-notification-count (user principal))
    (let
        ((inbox-notifications (get-user-inbox user)))
        (fold count-unread-notifications inbox-notifications u0)
    )
)

;; Helper function to count unread notifications
(define-private (count-unread-notifications (notification-id (optional uint)) (count uint))
    (match notification-id
        id (match (map-get? Notifications id)
            notification (if (not (get read notification))
                (+ count u1)
                count
            )
            count
        )
        count
    )
)

(define-read-only (get-daily-notification-count (user principal))
    (let ((current-day (/ stacks-block-height u144)))
        (default-to u0 (map-get? DailyNotificationCounts { user: user, day: current-day }))
    )
)

(define-read-only (get-notification-statistics (user principal))
    (ok {
        daily-count: (get-daily-notification-count user),
        unread-count: (get-unread-notification-count user),
        total-notifications: (default-to u0 (map-get? UserInboxCounters user))
    })
)
