import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const customer = accounts.get("wallet_1")!;
const courier = accounts.get("wallet_2")!;
const thirdParty = accounts.get("wallet_3")!;

describe("DeliveryNotifications Contract", () => {
  
  describe("Initialization and Settings", () => {
    it("should initialize notification settings successfully", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "initialize-notification-settings",
        [
          Cl.bool(true),   // job-updates
          Cl.bool(true),   // payments
          Cl.bool(false),  // batches
          Cl.bool(true),   // disputes
          Cl.bool(false),  // email
          Cl.bool(true),   // push
          Cl.uint(25)      // max-daily
        ],
        customer
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should retrieve user notification settings", () => {
      // First initialize settings
      simnet.callPublicFn(
        "DeliveryNotifications",
        "initialize-notification-settings",
        [
          Cl.bool(true), Cl.bool(false), Cl.bool(true), 
          Cl.bool(false), Cl.bool(true), Cl.bool(false), 
          Cl.uint(30)
        ],
        customer
      );

      const { result } = simnet.callReadOnlyFn(
        "DeliveryNotifications",
        "get-user-notification-settings",
        [Cl.principal(customer)],
        customer
      );

      expect(result).toBeSome(
        Cl.tuple({
          "job-updates-enabled": Cl.bool(true),
          "payment-notifications": Cl.bool(false),
          "batch-notifications": Cl.bool(true),
          "dispute-alerts": Cl.bool(false),
          "email-notifications": Cl.bool(true),
          "push-notifications": Cl.bool(false),
          "max-notifications-per-day": Cl.uint(30)
        })
      );
    });
  });

  describe("Sending Notifications", () => {
    beforeEach(() => {
      // Initialize settings for test user
      simnet.callPublicFn(
        "DeliveryNotifications",
        "initialize-notification-settings",
        [
          Cl.bool(true), Cl.bool(true), Cl.bool(true),
          Cl.bool(true), Cl.bool(false), Cl.bool(true),
          Cl.uint(50)
        ],
        customer
      );
    });

    it("should send a job creation notification successfully", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(1), // NOTIFICATION_JOB_CREATED
          Cl.stringAscii("New Delivery Job"),
          Cl.stringAscii("Your delivery job has been created and is awaiting pickup."),
          Cl.some(Cl.uint(123)), // job-id
          Cl.none(), // batch-id
          Cl.uint(2) // PRIORITY_NORMAL
        ],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1));
    });

    it("should send a payment notification successfully", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(courier),
          Cl.uint(5), // NOTIFICATION_PAYMENT_RECEIVED
          Cl.stringAscii("Payment Received"),
          Cl.stringAscii("You have received payment for delivery job #456."),
          Cl.some(Cl.uint(456)),
          Cl.none(),
          Cl.uint(3) // PRIORITY_HIGH
        ],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1));
    });

    it("should reject invalid notification type", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(10), // Invalid type (only 1-8 supported)
          Cl.stringAscii("Test"),
          Cl.stringAscii("Test message"),
          Cl.none(),
          Cl.none(),
          Cl.uint(2)
        ],
        deployer
      );
      expect(result).toBeErr(Cl.uint(502)); // err-invalid-notification-type
    });

    it("should reject invalid priority level", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(1),
          Cl.stringAscii("Test"),
          Cl.stringAscii("Test message"),
          Cl.none(),
          Cl.none(),
          Cl.uint(5) // Invalid priority (only 1-4 supported)
        ],
        deployer
      );
      expect(result).toBeErr(Cl.uint(504)); // err-invalid-priority
    });

    it("should respect user notification preferences", () => {
      // Initialize user with job-updates disabled
      simnet.callPublicFn(
        "DeliveryNotifications",
        "initialize-notification-settings",
        [
          Cl.bool(false), // job-updates disabled
          Cl.bool(true), Cl.bool(true), Cl.bool(true),
          Cl.bool(false), Cl.bool(true), Cl.uint(50)
        ],
        thirdParty
      );

      // Try to send job update notification
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(thirdParty),
          Cl.uint(2), // NOTIFICATION_JOB_ACCEPTED
          Cl.stringAscii("Job Accepted"),
          Cl.stringAscii("Your job has been accepted by a courier."),
          Cl.some(Cl.uint(789)),
          Cl.none(),
          Cl.uint(2)
        ],
        deployer
      );
      expect(result).toBeErr(Cl.uint(500)); // err-not-authorized
    });
  });

  describe("Reading Notifications", () => {
    beforeEach(() => {
      // Set up test environment
      simnet.callPublicFn(
        "DeliveryNotifications",
        "initialize-notification-settings",
        [
          Cl.bool(true), Cl.bool(true), Cl.bool(true), Cl.bool(true),
          Cl.bool(false), Cl.bool(true), Cl.uint(50)
        ],
        customer
      );

      // Send a test notification
      simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(1),
          Cl.stringAscii("Test Notification"),
          Cl.stringAscii("This is a test notification message."),
          Cl.some(Cl.uint(100)),
          Cl.none(),
          Cl.uint(2)
        ],
        deployer
      );
    });

    it("should retrieve notification by ID", () => {
      const { result } = simnet.callReadOnlyFn(
        "DeliveryNotifications",
        "get-notification",
        [Cl.uint(1)],
        customer
      );

      expect(result).toBeSome(
        Cl.tuple({
          recipient: Cl.principal(customer),
          sender: Cl.principal(deployer),
          "notification-type": Cl.uint(1),
          title: Cl.stringAscii("Test Notification"),
          message: Cl.stringAscii("This is a test notification message."),
          "job-id": Cl.some(Cl.uint(100)),
          "batch-id": Cl.none(),
          priority: Cl.uint(2),
          read: Cl.bool(false),
          "created-at": Cl.uint(simnet.blockHeight),
          "expires-at": Cl.uint(simnet.blockHeight + 1440)
        })
      );
    });

    it("should return notification statistics", () => {
      const { result } = simnet.callReadOnlyFn(
        "DeliveryNotifications",
        "get-notification-statistics",
        [Cl.principal(customer)],
        customer
      );

      expect(result).toBeOk(
        Cl.tuple({
          "daily-count": Cl.uint(1),
          "unread-count": Cl.uint(1),
          "total-notifications": Cl.uint(1)
        })
      );
    });
  });

  describe("Marking Notifications as Read", () => {
    beforeEach(() => {
      // Set up test environment
      simnet.callPublicFn(
        "DeliveryNotifications",
        "initialize-notification-settings",
        [
          Cl.bool(true), Cl.bool(true), Cl.bool(true), Cl.bool(true),
          Cl.bool(false), Cl.bool(true), Cl.uint(50)
        ],
        customer
      );

      // Send test notifications
      simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(1),
          Cl.stringAscii("First Notification"),
          Cl.stringAscii("First test message."),
          Cl.some(Cl.uint(101)),
          Cl.none(),
          Cl.uint(2)
        ],
        deployer
      );

      simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(2),
          Cl.stringAscii("Second Notification"),
          Cl.stringAscii("Second test message."),
          Cl.some(Cl.uint(102)),
          Cl.none(),
          Cl.uint(3)
        ],
        deployer
      );
    });

    it("should mark single notification as read", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "mark-notification-read",
        [Cl.uint(1)],
        customer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify notification is marked as read
      const { result: notificationResult } = simnet.callReadOnlyFn(
        "DeliveryNotifications",
        "get-notification",
        [Cl.uint(1)],
        customer
      );

      expect(notificationResult).toBeSome(
        Cl.tuple({
          recipient: Cl.principal(customer),
          sender: Cl.principal(deployer),
          "notification-type": Cl.uint(1),
          title: Cl.stringAscii("First Notification"),
          message: Cl.stringAscii("First test message."),
          "job-id": Cl.some(Cl.uint(101)),
          "batch-id": Cl.none(),
          priority: Cl.uint(2),
          read: Cl.bool(true), // Should be true now
          "created-at": Cl.uint(simnet.blockHeight),
          "expires-at": Cl.uint(simnet.blockHeight + 1440)
        })
      );
    });

    it("should mark multiple notifications as read", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "mark-multiple-read",
        [Cl.list([Cl.uint(1), Cl.uint(2)])],
        customer
      );
      expect(result).toBeOk(Cl.list([Cl.bool(true), Cl.bool(true)]));
    });

    it("should reject marking notification as read by unauthorized user", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "mark-notification-read",
        [Cl.uint(1)],
        courier // Wrong user
      );
      expect(result).toBeErr(Cl.uint(500)); // err-not-authorized
    });
  });

  describe("Daily Limits and Rate Limiting", () => {
    beforeEach(() => {
      // Set up user with low daily limit for testing
      simnet.callPublicFn(
        "DeliveryNotifications",
        "initialize-notification-settings",
        [
          Cl.bool(true), Cl.bool(true), Cl.bool(true), Cl.bool(true),
          Cl.bool(false), Cl.bool(true), Cl.uint(2) // Low limit
        ],
        customer
      );
    });

    it("should respect daily notification limits", () => {
      // Send first notification (should succeed)
      const result1 = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(1), Cl.stringAscii("First"), Cl.stringAscii("Message 1"),
          Cl.none(), Cl.none(), Cl.uint(2)
        ],
        deployer
      );
      expect(result1.result).toBeOk(Cl.uint(1));

      // Send second notification (should succeed)
      const result2 = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(2), Cl.stringAscii("Second"), Cl.stringAscii("Message 2"),
          Cl.none(), Cl.none(), Cl.uint(2)
        ],
        deployer
      );
      expect(result2.result).toBeOk(Cl.uint(2));

      // Send third notification (should fail due to daily limit)
      const result3 = simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(3), Cl.stringAscii("Third"), Cl.stringAscii("Message 3"),
          Cl.none(), Cl.none(), Cl.uint(2)
        ],
        deployer
      );
      expect(result3.result).toBeErr(Cl.uint(500)); // err-not-authorized
    });

    it("should track daily notification count correctly", () => {
      // Send one notification
      simnet.callPublicFn(
        "DeliveryNotifications",
        "send-notification",
        [
          Cl.principal(customer),
          Cl.uint(1), Cl.stringAscii("Test"), Cl.stringAscii("Test message"),
          Cl.none(), Cl.none(), Cl.uint(2)
        ],
        deployer
      );

      const { result } = simnet.callReadOnlyFn(
        "DeliveryNotifications",
        "get-daily-notification-count",
        [Cl.principal(customer)],
        customer
      );
      expect(result).toBeUint(1);
    });
  });

  describe("Admin Functions", () => {
    it("should allow contract owner to cleanup expired notifications", () => {
      // This is a basic test - in reality, we'd need to advance time to create expired notifications
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "cleanup-expired-notifications",
        [Cl.list([Cl.uint(1), Cl.uint(2)])],
        deployer // Contract owner
      );
      expect(result).toBeOk(Cl.list([Cl.bool(false), Cl.bool(false)])); // No expired notifications to clean up
    });

    it("should reject cleanup from non-owner", () => {
      const { result } = simnet.callPublicFn(
        "DeliveryNotifications",
        "cleanup-expired-notifications",
        [Cl.list([Cl.uint(1)])],
        customer // Not the owner
      );
      expect(result).toBeErr(Cl.uint(500)); // err-not-authorized
    });
  });

  describe("Edge Cases", () => {
    it("should handle non-existent notification ID gracefully", () => {
      const { result } = simnet.callReadOnlyFn(
        "DeliveryNotifications",
        "get-notification",
        [Cl.uint(999)], // Non-existent ID
        customer
      );
      expect(result).toBeNone();
    });

    it("should handle user with no notifications", () => {
      const { result } = simnet.callReadOnlyFn(
        "DeliveryNotifications",
        "get-notification-statistics",
        [Cl.principal(thirdParty)], // User with no notifications
        thirdParty
      );
      expect(result).toBeOk(
        Cl.tuple({
          "daily-count": Cl.uint(0),
          "unread-count": Cl.uint(0),
          "total-notifications": Cl.uint(0)
        })
      );
    });
  });
});
