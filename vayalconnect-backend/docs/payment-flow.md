# VayalConnect — Payment & Payout Architecture

This document describes the complete lifecycle of money across the VayalConnect platform, from Buyer checkout through Razorpay payment gateway to Admin approval and Farmer payout (via RazorpayX).

---

## 1. Core Financial Rules & Invariants

1. **Integer Paise Only**: Every amount in the backend is represented and stored as an integer number of paise (`1 INR = 100 paise`). Floats are strictly prohibited.
2. **Platform Balance Invariant**:
   $$\text{Buyer Total} = \text{Farmer Payout} + \text{Platform Commission}$$
   This invariant is verified before persisting any product snapshot or finalizing any order.
3. **Server-Side Price Authority**: The mobile app NEVER submits prices or totals. All calculations occur inside `app.services.pricing_service.PricingEngine`.
4. **Idempotency**: All payment verifications and payout requests use cryptographically unique idempotency keys.

---

## 2. Buyer Payment Flow (Razorpay PG)

```mermaid
sequenceDiagram
    autonumber
    actor Buyer as Buyer App
    participant BE as VayalConnect Backend
    participant DB as MongoDB Atlas
    participant RZP as Razorpay Gateway

    Buyer->>BE: POST /api/v1/orders (product_id, quantity)
    BE->>DB: Atomic inventory reservation & Pricing snapshot
    BE->>DB: Save Order (Status: PENDING_PAYMENT)
    BE-->>Buyer: Order Created (order_id, buyer_total_paise)

    Buyer->>BE: POST /api/v1/payments/create (order_id)
    BE->>DB: Fetch order (validate buyer ownership)
    BE->>RZP: Create Order (amount_paise from DB)
    RZP-->>BE: razorpay_order_id
    BE->>DB: Save Payment record (Status: CREATED)
    BE-->>Buyer: {razorpay_order_id, amount_paise}

    Buyer->>RZP: Open Razorpay SDK & Complete Payment
    RZP-->>Buyer: {razorpay_payment_id, razorpay_signature}

    Buyer->>BE: POST /api/v1/payments/verify
    Note over BE: Verify HMAC-SHA256 signature
    BE->>DB: Mark Payment: CAPTURED
    BE->>DB: Update Order: PAID
    BE->>DB: Generate Payout Record (PENDING_APPROVAL)
    BE-->>Buyer: Payment Success Confirmed
```

---

## 3. Farmer Payout Flow (RazorpayX / Bank Transfer)

Payouts are **NOT** automated directly upon buyer payment to prevent fraud, dispute mismanagement, or defective crop delivery. Payouts require an audited Admin approval workflow:

```mermaid
sequenceDiagram
    autonumber
    actor Admin as Admin Dashboard
    participant BE as VayalConnect Backend
    participant DB as MongoDB Atlas
    participant RZPX as RazorpayX / Bank Gateway
    actor Farmer as Farmer App

    BE->>DB: Order marked PAID -> Create Payout (PENDING_APPROVAL)
    Admin->>BE: GET /api/v1/payouts?status=PENDING_APPROVAL
    BE-->>Admin: List of pending farmer payouts with order details

    Admin->>BE: POST /api/v1/payouts/{id}/approve
    BE->>DB: Update Payout: APPROVED (recorded with admin_id, timestamp)
    BE->>DB: Update Order Payout Status: APPROVED

    Admin->>BE: POST /api/v1/payouts/{id}/process
    BE->>DB: Decrypt farmer's bank details (Fernet)
    BE->>RZPX: Initiate Bank Transfer / Fund Account Payout
    RZPX-->>BE: Transfer Acknowledged (utr, status: PROCESSING)
    BE->>DB: Update Payout: PROCESSING
    BE-->>Admin: Payout Processed

    Note over BE, Farmer: Webhook / Polling receives final SETTLED status
    BE->>DB: Update Payout: COMPLETED
    Farmer->>BE: GET /api/v1/farmers/dashboard
    BE-->>Farmer: Total Earnings & Settled Payouts Updated
```

---

## 4. Razorpay Webhook Idempotency

When Razorpay triggers asynchronous webhook events (e.g. `payment.captured` or `payout.processed`):
1. The backend verifies the `X-Razorpay-Signature` against `RAZORPAY_WEBHOOK_SECRET`.
2. The payload's event ID is evaluated against existing records to discard duplicate deliveries.
3. If the payment was already captured by the synchronous verify endpoint, the webhook exits cleanly without secondary side effects.
