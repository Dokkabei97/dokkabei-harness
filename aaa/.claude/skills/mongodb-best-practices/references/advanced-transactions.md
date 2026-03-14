---
title: Use Multi-Document Transactions Judiciously with Performance Awareness
impact: LOW
impactDescription: ACID guarantees across documents with 2-5x write latency overhead
tags: transactions, multi-document, acid, session, write-conflicts
---

## Use Multi-Document Transactions Judiciously with Performance Awareness

Multi-document transactions provide ACID guarantees across multiple documents and collections. However, they come with significant performance overhead. Use them only when atomicity across documents is truly required.

**Incorrect (transaction for single-document operations):**

```javascript
// Unnecessary transaction — single document operations are already atomic
const session = client.startSession();
session.startTransaction();
try {
  await db.users.updateOne(
    { _id: userId },
    { $set: { name: "New Name", email: "new@email.com" } },
    { session }
  );
  await session.commitTransaction();
} finally {
  session.endSession();
}
// Single updateOne is already atomic — transaction adds overhead for no benefit
```

**Correct (transaction only when cross-document atomicity is needed):**

```javascript
// Transfer money between accounts — must be all-or-nothing
const session = client.startSession();

try {
  session.startTransaction({
    readConcern: { level: "snapshot" },
    writeConcern: { w: "majority" },
    maxCommitTimeMS: 5000  // prevent long-running transactions
  });

  // Debit source account
  const debitResult = await db.accounts.updateOne(
    { _id: sourceId, balance: { $gte: amount } },  // check sufficient funds
    { $inc: { balance: -amount } },
    { session }
  );

  if (debitResult.modifiedCount === 0) {
    await session.abortTransaction();
    throw new Error("Insufficient funds");
  }

  // Credit destination account
  await db.accounts.updateOne(
    { _id: destId },
    { $inc: { balance: amount } },
    { session }
  );

  // Record the transfer
  await db.transfers.insertOne({
    from: sourceId, to: destId, amount, ts: new Date()
  }, { session });

  await session.commitTransaction();
} catch (err) {
  if (session.transaction.isActive) {
    await session.abortTransaction();
  }
  // Handle TransientTransactionError with retry
  if (err.hasErrorLabel?.("TransientTransactionError")) {
    // Retry the entire transaction
  }
  throw err;
} finally {
  session.endSession();
}
```

**When to use vs. avoid transactions:**

| Use Transactions | Avoid Transactions |
|---|---|
| Cross-collection atomic writes | Single document updates |
| Financial transfers | Logging / analytics |
| Inventory reservation + order creation | Schema designed for embedding |
| Multi-step workflows requiring rollback | Eventual consistency is acceptable |

Transaction limitations:
- 16MB total size for all operations in a transaction
- Default 60-second lifetime (configurable with `transactionLifetimeLimitSeconds`)
- Write conflicts cause abort — design to minimize contention
- Not available on standalone instances (requires replica set)

Reference: [Transactions](https://www.mongodb.com/docs/manual/core/transactions/)
