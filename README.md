# DecentralizedDelivery

A comprehensive Stacks blockchain-based last-mile delivery platform with real-time notifications, route optimization, and secure payment systems.

## Features

### Core Delivery Platform (DecentralizedDelivery.clar)
- **Courier Management**: Stake-based system with reputation scoring
- **Delivery Jobs**: Complete lifecycle from creation to completion
- **Service Areas**: Geographic-based delivery zones with customizable requirements
- **Payment Systems**: Multiple secure payment options including escrow
- **Rating & Reviews**: Bi-directional rating system for customers and couriers
- **Dispute Resolution**: Built-in dispute filing and resolution mechanisms
- **Package Tracking**: Real-time tracking with proof-of-delivery
- **Multi-signature Verification**: Enhanced security for high-value deliveries
- **Insurance Pool**: Courier protection with claim mechanisms
- **Dynamic Pricing**: Demand-based pricing adjustments

### Route Optimization (RouteOptimization.clar)
- **Delivery Batching**: Efficient grouping of delivery jobs
- **Route Optimization**: Algorithm-driven route planning
- **Efficiency Bonuses**: Rewards for optimal delivery batching
- **Performance Analytics**: Courier efficiency tracking and statistics

### 🆕 Real-Time Notifications (DeliveryNotifications.clar)
- **Notification Management**: Structured system for delivery event notifications
- **User Preferences**: Customizable notification settings per user
- **Priority Levels**: Four-tier priority system (Low, Normal, High, Urgent)
- **Rate Limiting**: Daily notification limits to prevent spam
- **Inbox System**: Circular buffer storing last 20 notifications per user
- **Read Status Tracking**: Mark individual or multiple notifications as read
- **Event Types**: Support for 8 different notification types:
  - Job Created
  - Job Accepted
  - Job Started
  - Job Completed
  - Payment Received
  - Rating Received
  - Dispute Filed
  - Batch Optimized

## Getting Started

### Prerequisites
- [Clarinet](https://docs.hiro.so/clarinet/) installed
- Node.js and npm for running tests

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/DecentralizedDelivery.git
   cd DecentralizedDelivery
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Run tests:
   ```bash
   npm test
   ```

### Contract Deployment

The project includes three main contracts:
- `DecentralizedDelivery.clar` - Core delivery platform
- `RouteOptimization.clar` - Route optimization and batching
- `DeliveryNotifications.clar` - Real-time notification management

Use Clarinet to deploy:
```bash
clarinet deploy
```

## Usage Examples

### Setting Up Notifications

```javascript
// Initialize notification preferences
const result = await callContractFunction({
  contractAddress: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM',
  contractName: 'DeliveryNotifications',
  functionName: 'initialize-notification-settings',
  functionArgs: [
    boolCV(true),  // job-updates
    boolCV(true),  // payments
    boolCV(false), // batches
    boolCV(true),  // disputes
    boolCV(false), // email
    boolCV(true),  // push
    uintCV(50)     // max-daily
  ]
});
```

### Sending Notifications

```javascript
// Send a job completion notification
const notification = await callContractFunction({
  contractAddress: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM',
  contractName: 'DeliveryNotifications',
  functionName: 'send-notification',
  functionArgs: [
    principalCV('ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG'), // recipient
    uintCV(4),                                                  // NOTIFICATION_JOB_COMPLETED
    stringAsciiCV("Delivery Complete!"),                       // title
    stringAsciiCV("Your package has been delivered safely."),  // message
    someCV(uintCV(123)),                                       // job-id
    noneCV(),                                                  // batch-id
    uintCV(3)                                                  // PRIORITY_HIGH
  ]
});
```

## Architecture

The DecentralizedDelivery platform uses a modular architecture:

```
┌─────────────────────────────────┐
│     Frontend Application        │
└─────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│        Stacks Blockchain        │
├─────────────────────────────────┤
│   DeliveryNotifications.clar    │ ◄── New Feature!
├─────────────────────────────────┤
│   DecentralizedDelivery.clar    │
├─────────────────────────────────┤
│    RouteOptimization.clar       │
└─────────────────────────────────┘
```

### Key Benefits of the Notification System

1. **Enhanced User Experience**: Real-time updates keep users informed
2. **Customizable Preferences**: Users control what notifications they receive
3. **Spam Prevention**: Built-in rate limiting and daily limits
4. **Integration Ready**: Easy integration with existing delivery workflows
5. **Scalable Design**: Efficient circular buffer system for inbox management
6. **Developer Friendly**: Comprehensive test suite and clear API

## Testing

Run the complete test suite:
```bash
npm test
```

Run tests with coverage:
```bash
npm run test:report
```

Watch mode for development:
```bash
npm run test:watch
```

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests for any improvements.

## License

ISC License - see LICENSE file for details.
