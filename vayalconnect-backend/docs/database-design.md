# VayalConnect — Database Design

## Collections

### 1. `users`
Primary identity collection for all roles.

```json
{
  "_id": "ObjectId",
  "name": "string",
  "email": "string (unique, indexed)",
  "phone": "string (unique, indexed)",
  "password_hash": "string",
  "address": "string",
  "area_location": "string",
  "gender": "string (enum: male, female, other)",
  "age": "int",
  "role": "string (enum: FARMER, BUYER, ADMIN) (indexed)",
  "email_verified": "bool",
  "is_active": "bool",
  "is_approved": "bool (for farmers needing admin approval)",
  "preferred_language": "string (en, ta)",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `email` (unique), `phone` (unique), `role`, `is_active`

---

### 2. `farmer_profiles`
Extended farmer-specific data including bank details.

```json
{
  "_id": "ObjectId",
  "user_id": "ObjectId (unique, indexed, ref: users)",
  "bank_account_holder_name": "string (encrypted)",
  "bank_name": "string (encrypted)",
  "bank_account_number": "string (encrypted)",
  "bank_ifsc": "string (encrypted)",
  "upi_id": "string (encrypted, optional)",
  "bank_details_verified": "bool",
  "approval_status": "string (enum: PENDING, APPROVED, REJECTED)",
  "approved_by": "ObjectId (nullable, ref: users)",
  "approved_at": "datetime (nullable)",
  "rejection_reason": "string (nullable)",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `user_id` (unique), `approval_status`

---

### 3. `buyer_profiles`
Extended buyer-specific data.

```json
{
  "_id": "ObjectId",
  "user_id": "ObjectId (unique, indexed, ref: users)",
  "business_name": "string (optional)",
  "business_type": "string (optional)",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `user_id` (unique)

---

### 4. `products`
Farmer-listed products with embedded pricing snapshot.

```json
{
  "_id": "ObjectId",
  "farmer_id": "ObjectId (indexed, ref: users)",
  "product_name": "string (indexed)",
  "category": "string (indexed)",
  "quantity_available": "int (in base unit, e.g., grams)",
  "quantity_unit": "string (enum: KG, QUINTAL, TON, PIECE, DOZEN)",
  "quality_grade": "string (enum: A, B, C, PREMIUM)",
  "image_url": "string (nullable)",
  "location": "string",
  "market": "string",
  "harvest_date": "date",
  "government_reference_price_paise": "int",
  "reference_price_date": "date",
  "reference_price_source": "string",
  "farmer_payout_per_unit_paise": "int",
  "buyer_price_per_unit_paise": "int",
  "commission_percentage": "int (basis points, e.g., 1500 = 15%)",
  "commission_per_unit_paise": "int",
  "pricing_policy_id": "ObjectId",
  "pricing_policy_version": "int",
  "pricing_snapshot_id": "ObjectId (ref: pricing_snapshots)",
  "status": "string (enum: ACTIVE, INACTIVE, OUT_OF_STOCK, SUSPENDED)",
  "is_active": "bool",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `farmer_id`, `product_name`, `category`, `status`, `is_active`, `location`

---

### 5. `market_prices`
Cached Government market price data.

```json
{
  "_id": "ObjectId",
  "commodity": "string (indexed)",
  "market": "string (indexed)",
  "state": "string",
  "district": "string",
  "variety": "string",
  "grade": "string",
  "min_price_paise": "int",
  "max_price_paise": "int",
  "modal_price_paise": "int",
  "unit": "string",
  "arrival_date": "date (indexed)",
  "source": "string",
  "source_record_id": "string (nullable)",
  "retrieved_at": "datetime",
  "created_at": "datetime"
}
```
**Indexes**: `commodity` + `market` + `arrival_date` (compound), `arrival_date`, `commodity`

---

### 6. `pricing_policies`
Configurable pricing rule definitions.

```json
{
  "_id": "ObjectId",
  "name": "string",
  "description": "string",
  "farmer_payout_percentage": "int (basis points, e.g., 7000 = 70%)",
  "buyer_price_percentage": "int (basis points, e.g., 9000 = 90%)",
  "version": "int",
  "is_active": "bool",
  "created_by": "ObjectId",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `is_active`, `version`

---

### 7. `commission_configs`
Admin-managed commission percentage history.

```json
{
  "_id": "ObjectId",
  "commission_percentage": "int (basis points, e.g., 1500 = 15%)",
  "effective_from": "datetime",
  "effective_until": "datetime (nullable — null means currently active)",
  "created_by": "ObjectId (ref: users, admin)",
  "status": "string (enum: ACTIVE, SUPERSEDED)",
  "version": "int",
  "created_at": "datetime"
}
```
**Indexes**: `status`, `effective_from`, `version`

---

### 8. `pricing_snapshots`
Immutable record of all pricing calculations at transaction time.

```json
{
  "_id": "ObjectId",
  "product_id": "ObjectId (indexed)",
  "farmer_id": "ObjectId",
  "government_reference_price_paise": "int",
  "reference_price_unit": "string",
  "reference_price_date": "date",
  "reference_price_source": "string",
  "farmer_payout_per_unit_paise": "int",
  "buyer_price_per_unit_paise": "int",
  "commission_percentage_bps": "int",
  "commission_per_unit_paise": "int",
  "pricing_policy_id": "ObjectId",
  "pricing_policy_version": "int",
  "commission_config_id": "ObjectId",
  "commission_config_version": "int",
  "market": "string",
  "location": "string",
  "quality_grade": "string",
  "calculated_at": "datetime",
  "created_at": "datetime"
}
```
**Indexes**: `product_id`, `farmer_id`, `created_at`

> **IMMUTABILITY**: Once created, pricing snapshots are NEVER updated.

---

### 9. `orders`
Complete order records with frozen financial data.

```json
{
  "_id": "ObjectId",
  "order_number": "string (unique, human-readable)",
  "buyer_id": "ObjectId (indexed)",
  "farmer_id": "ObjectId (indexed)",
  "product_id": "ObjectId (indexed)",
  "pricing_snapshot_id": "ObjectId (ref: pricing_snapshots)",
  "quantity": "int (in display units)",
  "quantity_unit": "string",
  "buyer_unit_price_paise": "int",
  "buyer_total_paise": "int",
  "farmer_unit_payout_paise": "int",
  "farmer_total_payout_paise": "int",
  "commission_percentage_bps": "int",
  "commission_unit_amount_paise": "int",
  "commission_total_paise": "int",
  "government_reference_price_paise": "int",
  "reference_price_date": "date",
  "order_status": "string (enum: PENDING_PAYMENT, PAID, CONFIRMED, PROCESSING, COMPLETED, CANCELLED, REFUNDED)",
  "payment_status": "string (enum: PENDING, PROCESSING, COMPLETED, FAILED, REFUNDED)",
  "payout_status": "string (enum: NOT_INITIATED, PENDING_APPROVAL, APPROVED, PROCESSING, PAID, FAILED, REJECTED)",
  "idempotency_key": "string (unique, indexed)",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `buyer_id`, `farmer_id`, `product_id`, `order_status`, `payment_status`, `payout_status`, `order_number` (unique), `idempotency_key` (unique), `created_at`

> **IMMUTABILITY**: Financial fields (all `*_paise`, `commission_*`, `government_*`) are NEVER updated after creation.

---

### 10. `payments`
Razorpay payment tracking.

```json
{
  "_id": "ObjectId",
  "order_id": "ObjectId (indexed, ref: orders)",
  "buyer_id": "ObjectId (indexed)",
  "razorpay_order_id": "string (unique, indexed)",
  "razorpay_payment_id": "string (nullable, indexed)",
  "razorpay_signature": "string (nullable)",
  "signature_verified": "bool",
  "amount_paise": "int",
  "currency": "string (default: INR)",
  "payment_status": "string (enum: CREATED, AUTHORIZED, CAPTURED, FAILED, REFUNDED)",
  "failure_reason": "string (nullable)",
  "payment_method": "string (nullable)",
  "refund_id": "string (nullable)",
  "refund_amount_paise": "int (nullable)",
  "idempotency_key": "string (unique, indexed)",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `order_id`, `buyer_id`, `razorpay_order_id` (unique), `razorpay_payment_id`, `payment_status`, `idempotency_key` (unique)

---

### 11. `payouts`
Farmer payout tracking.

```json
{
  "_id": "ObjectId",
  "payout_number": "string (unique)",
  "order_id": "ObjectId (indexed, ref: orders)",
  "farmer_id": "ObjectId (indexed, ref: users)",
  "amount_paise": "int",
  "currency": "string (default: INR)",
  "status": "string (enum: PENDING_APPROVAL, APPROVED, REJECTED, PROCESSING, PAID, FAILED)",
  "approved_by": "ObjectId (nullable, ref: users admin)",
  "approved_at": "datetime (nullable)",
  "rejection_reason": "string (nullable)",
  "provider": "string (e.g., razorpay, sandbox)",
  "provider_reference_id": "string (nullable)",
  "provider_status": "string (nullable)",
  "processed_at": "datetime (nullable)",
  "paid_at": "datetime (nullable)",
  "failure_reason": "string (nullable)",
  "retry_count": "int (default: 0)",
  "idempotency_key": "string (unique, indexed)",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```
**Indexes**: `order_id`, `farmer_id`, `status`, `payout_number` (unique), `idempotency_key` (unique)

---

### 12. `otp_verifications`
OTP tracking with security controls.

```json
{
  "_id": "ObjectId",
  "email": "string (indexed)",
  "otp_hash": "string",
  "purpose": "string (enum: REGISTRATION, PASSWORD_RESET, LOGIN)",
  "attempts": "int (default: 0)",
  "max_attempts": "int (default: 5)",
  "expires_at": "datetime (TTL indexed)",
  "is_used": "bool",
  "created_at": "datetime"
}
```
**Indexes**: `email` + `purpose` (compound), `expires_at` (TTL)

---

### 13. `refresh_tokens`
Session/token management.

```json
{
  "_id": "ObjectId",
  "user_id": "ObjectId (indexed)",
  "token_hash": "string (unique, indexed)",
  "device_info": "string (nullable)",
  "expires_at": "datetime (TTL indexed)",
  "is_revoked": "bool",
  "created_at": "datetime"
}
```
**Indexes**: `user_id`, `token_hash` (unique), `expires_at` (TTL)

---

### 14. `audit_logs`
Immutable action log.

```json
{
  "_id": "ObjectId",
  "actor_id": "ObjectId (indexed)",
  "actor_role": "string",
  "action": "string (indexed)",
  "entity_type": "string (indexed)",
  "entity_id": "string",
  "details": "object (before/after, safe fields only)",
  "request_id": "string",
  "ip_address": "string (nullable)",
  "timestamp": "datetime (indexed)",
  "created_at": "datetime"
}
```
**Indexes**: `actor_id`, `action`, `entity_type`, `timestamp`, `entity_type` + `entity_id` (compound)

> **NEVER log**: passwords, OTPs, API keys, full bank account numbers, secrets.

---

### 15. `admin_actions`
Admin-specific workflow tracking.

```json
{
  "_id": "ObjectId",
  "admin_id": "ObjectId (indexed)",
  "action_type": "string (enum: APPROVE_FARMER, REJECT_FARMER, APPROVE_PAYOUT, REJECT_PAYOUT, CHANGE_COMMISSION, SUSPEND_PRODUCT, etc.)",
  "target_entity_type": "string",
  "target_entity_id": "ObjectId",
  "details": "object",
  "created_at": "datetime"
}
```
**Indexes**: `admin_id`, `action_type`, `created_at`

---

## Index Strategy Summary

| Collection        | Key Indexes                                          |
|-------------------|------------------------------------------------------|
| users             | email(u), phone(u), role, is_active                  |
| farmer_profiles   | user_id(u), approval_status                          |
| buyer_profiles    | user_id(u)                                           |
| products          | farmer_id, category, status, location                |
| market_prices     | commodity+market+arrival_date(c), commodity          |
| pricing_policies  | is_active                                            |
| commission_configs| status, effective_from                               |
| pricing_snapshots | product_id, farmer_id                                |
| orders            | buyer_id, farmer_id, order_number(u), order_status   |
| payments          | order_id, razorpay_order_id(u), payment_status       |
| payouts           | order_id, farmer_id, status, payout_number(u)        |
| otp_verifications | email+purpose(c), expires_at(TTL)                    |
| refresh_tokens    | user_id, token_hash(u), expires_at(TTL)              |
| audit_logs        | actor_id, action, entity_type, timestamp             |

**(u)** = unique, **(c)** = compound

## Data Integrity Rules

1. **Financial immutability**: Once an order is created, `*_paise`, `commission_*`, and `government_*` fields are NEVER modified
2. **Snapshot binding**: Every order references a `pricing_snapshot_id` — the snapshot is the source of truth
3. **Consistency check**: `buyer_total_paise == farmer_total_payout_paise + commission_total_paise`
4. **No unbounded arrays**: All related data stored in separate collections with foreign keys
5. **TTL cleanup**: OTPs and refresh tokens auto-expire via MongoDB TTL indexes
