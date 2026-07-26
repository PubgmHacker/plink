-- PATCH 16: App Store Server API V2 + Admin APIs
-- Add fields for JWS transaction verification + admin moderation

-- Subscription: add App Store Server API V2 fields
ALTER TABLE "Subscription" ADD COLUMN "originalTransactionId" TEXT;
ALTER TABLE "Subscription" ADD COLUMN "environment" TEXT;
ALTER TABLE "Subscription" ADD COLUMN "revokedAt" DATETIME(3);
ALTER TABLE "Subscription" ADD COLUMN "lastVerifiedAt" DATETIME(3);

CREATE INDEX "Subscription_userID_isActive_idx" ON "Subscription"("userID", "isActive");
CREATE INDEX "Subscription_originalTransactionId_idx" ON "Subscription"("originalTransactionId");

-- TransactionRecord: new model for signed JWS storage
CREATE TABLE "TransactionRecord" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "transactionId" TEXT NOT NULL,
    "originalTransactionId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "environment" TEXT NOT NULL,
    "jws" TEXT NOT NULL,
    "expiresAt" DATETIME(3),
    "revocationDate" DATETIME(3),
    "verifiedAt" DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TransactionRecord_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "TransactionRecord_transactionId_key" UNIQUE ("transactionId")
);

CREATE INDEX "TransactionRecord_userId_createdAt_idx" ON "TransactionRecord"("userId", "createdAt");
CREATE INDEX "TransactionRecord_originalTransactionId_idx" ON "TransactionRecord"("originalTransactionId");
CREATE INDEX "TransactionRecord_productId_idx" ON "TransactionRecord"("productId");

-- Add foreign key
ALTER TABLE "TransactionRecord" ADD CONSTRAINT "TransactionRecord_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Report: add moderation fields
ALTER TABLE "Report" ADD COLUMN "status" TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE "Report" ADD COLUMN "resolvedAt" DATETIME(3);
ALTER TABLE "Report" ADD COLUMN "resolvedBy" TEXT;

CREATE INDEX "Report_status_createdAt_idx" ON "Report"("status", "createdAt");

-- Add foreign key for resolver
ALTER TABLE "Report" ADD CONSTRAINT "Report_resolvedBy_fkey"
    FOREIGN KEY ("resolvedBy") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
