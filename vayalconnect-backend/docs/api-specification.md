# VayalConnect — API Specification

## Base URL
```
https://<render-domain>/api/v1
```

## Authentication
All protected endpoints require:
```
Authorization: Bearer <access_token>
```

## Response Format
### Success
```json
{
  "success": true,
  "data": { ... },
  "request_id": "uuid"
}
```
### Error
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message"
  },
  "request_id": "uuid"
}
```

---

## 1. Authentication (`/api/v1/auth`)

| Method | Endpoint               | Auth | Roles | Description                    |
|--------|------------------------|------|-------|--------------------------------|
| POST   | /register              | No   | —     | Register new user              |
| POST   | /request-otp           | No   | —     | Send OTP to email              |
| POST   | /verify-otp            | No   | —     | Verify email OTP               |
| POST   | /select-role           | JWT  | Any   | Choose FARMER/BUYER role       |
| POST   | /login                 | No   | —     | Login with email/password      |
| POST   | /refresh               | No   | —     | Refresh access token           |
| POST   | /logout                | JWT  | Any   | Invalidate refresh token       |
| POST   | /forgot-password       | No   | —     | Request password reset OTP     |
| POST   | /reset-password        | No   | —     | Reset password with OTP        |

### POST /register
```json
// Request
{
  "name": "string",
  "email": "string",
  "phone": "string",
  "password": "string (min 8 chars)",
  "address": "string",
  "area_location": "string",
  "gender": "male|female|other",
  "age": "int",
  "preferred_language": "en|ta"
}
// Response 201
{
  "success": true,
  "data": {
    "user_id": "string",
    "message": "Registration successful. Please verify your email."
  }
}
```

### POST /request-otp
```json
// Request
{ "email": "string", "purpose": "REGISTRATION|PASSWORD_RESET" }
// Response 200
{ "success": true, "data": { "message": "OTP sent to email." } }
```

### POST /verify-otp
```json
// Request
{ "email": "string", "otp": "string", "purpose": "REGISTRATION|PASSWORD_RESET" }
// Response 200
{ "success": true, "data": { "verified": true } }
```

### POST /select-role
```json
// Request (JWT required, email must be verified)
{ "role": "FARMER|BUYER" }
// Response 200
{ "success": true, "data": { "role": "FARMER", "message": "Role assigned." } }
```

### POST /login
```json
// Request
{ "email": "string", "password": "string" }
// Response 200
{
  "success": true,
  "data": {
    "access_token": "string",
    "refresh_token": "string",
    "token_type": "bearer",
    "expires_in": 1800,
    "user": {
      "id": "string",
      "name": "string",
      "email": "string",
      "role": "FARMER|BUYER|ADMIN"
    }
  }
}
```

---

## 2. Users (`/api/v1/users`)

| Method | Endpoint      | Auth | Roles        | Description           |
|--------|---------------|------|--------------|-----------------------|
| GET    | /me           | JWT  | Any          | Get current user      |
| PUT    | /me           | JWT  | Any          | Update profile        |
| PUT    | /me/password  | JWT  | Any          | Change password       |
| PUT    | /me/language  | JWT  | Any          | Change language pref  |

---

## 3. Farmers (`/api/v1/farmers`)

| Method | Endpoint           | Auth | Roles  | Description              |
|--------|--------------------|------|--------|--------------------------|
| GET    | /me/profile        | JWT  | FARMER | Get farmer profile       |
| PUT    | /me/profile        | JWT  | FARMER | Update farmer profile    |
| GET    | /me/bank           | JWT  | FARMER | Get own bank details     |
| PUT    | /me/bank           | JWT  | FARMER | Update bank details      |
| GET    | /me/dashboard      | JWT  | FARMER | Dashboard summary        |
| GET    | /me/payouts        | JWT  | FARMER | List own payouts         |
| GET    | /me/payouts/{id}   | JWT  | FARMER | Get payout detail        |
| GET    | /me/transactions   | JWT  | FARMER | Transaction history      |

### PUT /me/bank
```json
// Request
{
  "account_holder_name": "string",
  "bank_name": "string",
  "account_number": "string",
  "ifsc": "string",
  "upi_id": "string (optional)"
}
// Response 200 — masked bank details returned
{
  "success": true,
  "data": {
    "bank_name": "State Bank of India",
    "account_number_masked": "XXXX1234",
    "ifsc": "SBIN0001234",
    "upi_id_masked": "XXXX@upi"
  }
}
```

---

## 4. Products (`/api/v1/products`)

| Method | Endpoint         | Auth | Roles         | Description                     |
|--------|------------------|------|---------------|---------------------------------|
| POST   | /                | JWT  | FARMER        | Create product (triggers pricing)|
| GET    | /                | JWT  | BUYER/ADMIN   | List available products         |
| GET    | /{id}            | JWT  | Any           | Product detail (role-filtered)  |
| PUT    | /{id}            | JWT  | FARMER (owner)| Update own product              |
| DELETE | /{id}            | JWT  | FARMER/ADMIN  | Deactivate product              |
| GET    | /my              | JWT  | FARMER        | List own products               |

### POST / (Create Product — Farmer)
```json
// Request
{
  "product_name": "string",
  "category": "string",
  "quantity": "number",
  "quantity_unit": "KG|QUINTAL|TON|PIECE|DOZEN",
  "quality_grade": "A|B|C|PREMIUM",
  "image_url": "string (optional)",
  "location": "string",
  "market": "string",
  "harvest_date": "YYYY-MM-DD"
}
// Response 201 — FARMER-SAFE (no gov price, no buyer price, no commission)
{
  "success": true,
  "data": {
    "product_id": "string",
    "product_name": "Tomato",
    "quantity": 100,
    "quantity_unit": "KG",
    "quality_grade": "A",
    "farmer_payout_per_unit": "₹35.00",
    "farmer_payout_per_unit_paise": 3500,
    "status": "ACTIVE"
  }
}
```

### GET /{id} — Buyer Response
```json
{
  "product_id": "string",
  "product_name": "Tomato",
  "category": "Vegetables",
  "quantity_available": 100,
  "quantity_unit": "KG",
  "quality_grade": "A",
  "image_url": "string",
  "location": "Chennai",
  "farmer_name": "string",
  "buyer_price_per_unit": "₹45.00",
  "buyer_price_per_unit_paise": 4500,
  "harvest_date": "2025-01-15"
}
```
> **No farmer_payout, commission, gov_price in buyer response**

### GET /{id} — Admin Response
```json
{
  "product_id": "string",
  "product_name": "Tomato",
  "farmer_id": "string",
  "farmer_name": "string",
  "government_reference_price_paise": 5000,
  "farmer_payout_per_unit_paise": 3500,
  "buyer_price_per_unit_paise": 4500,
  "commission_percentage_bps": 1500,
  "commission_per_unit_paise": 1000,
  "pricing_policy_id": "string",
  "pricing_policy_version": 1,
  "...all fields"
}
```

---

## 5. Market Prices (`/api/v1/market-prices`)

| Method | Endpoint         | Auth | Roles | Description                  |
|--------|------------------|------|-------|------------------------------|
| GET    | /                | JWT  | ADMIN | Query market prices          |
| GET    | /commodities     | JWT  | ADMIN | List known commodities       |
| GET    | /markets         | JWT  | ADMIN | List known markets           |
| POST   | /refresh         | JWT  | ADMIN | Force refresh from gov API   |

---

## 6. Pricing (`/api/v1/pricing`)

| Method | Endpoint               | Auth | Roles | Description                |
|--------|------------------------|------|-------|----------------------------|
| GET    | /policies              | JWT  | ADMIN | List pricing policies      |
| POST   | /policies              | JWT  | ADMIN | Create pricing policy      |
| PUT    | /policies/{id}         | JWT  | ADMIN | Update pricing policy      |
| GET    | /commission            | JWT  | ADMIN | Get active commission      |
| PUT    | /commission            | JWT  | ADMIN | Update commission %        |
| GET    | /commission/history    | JWT  | ADMIN | Commission change history  |

### PUT /commission
```json
// Request
{ "commission_percentage_bps": 1000 }  // 10%
// Response
{
  "success": true,
  "data": {
    "previous_percentage_bps": 1500,
    "new_percentage_bps": 1000,
    "effective_from": "2025-01-20T10:00:00Z",
    "note": "Applies only to new transactions."
  }
}
```

---

## 7. Orders (`/api/v1/orders`)

| Method | Endpoint            | Auth | Roles       | Description             |
|--------|---------------------|------|-------------|-------------------------|
| POST   | /                   | JWT  | BUYER       | Create order            |
| GET    | /                   | JWT  | Any         | List orders (scoped)    |
| GET    | /{id}               | JWT  | Any         | Order detail (scoped)   |
| PUT    | /{id}/cancel        | JWT  | BUYER/ADMIN | Cancel order            |
| PUT    | /{id}/status        | JWT  | ADMIN       | Update order status     |

### POST / (Create Order — Buyer)
```json
// Request — ONLY product_id and quantity
{
  "product_id": "string",
  "quantity": 50,
  "idempotency_key": "uuid"
}
// Response 201
{
  "success": true,
  "data": {
    "order_id": "string",
    "order_number": "VC-20250120-001",
    "product_name": "Tomato",
    "quantity": 50,
    "unit": "KG",
    "unit_price_paise": 4500,
    "total_paise": 225000,
    "total_display": "₹2,250.00",
    "order_status": "PENDING_PAYMENT",
    "razorpay_order_id": "order_xxxx"
  }
}
```
> **Backend calculates all prices. Client sends ONLY product_id + quantity.**

---

## 8. Payments (`/api/v1/payments`)

| Method | Endpoint            | Auth | Roles  | Description               |
|--------|---------------------|------|--------|---------------------------|
| POST   | /verify             | JWT  | BUYER  | Verify Razorpay payment   |
| GET    | /{order_id}         | JWT  | Any    | Payment status (scoped)   |

### POST /verify
```json
// Request
{
  "order_id": "string",
  "razorpay_order_id": "string",
  "razorpay_payment_id": "string",
  "razorpay_signature": "string"
}
// Response 200
{
  "success": true,
  "data": {
    "payment_verified": true,
    "order_status": "PAID",
    "message": "Payment verified successfully."
  }
}
```

---

## 9. Payouts (`/api/v1/payouts`)

| Method | Endpoint             | Auth | Roles  | Description               |
|--------|----------------------|------|--------|---------------------------|
| GET    | /                    | JWT  | ADMIN  | List all payouts          |
| GET    | /{id}                | JWT  | ADMIN/FARMER| Payout detail (scoped)|
| PUT    | /{id}/approve        | JWT  | ADMIN  | Approve payout            |
| PUT    | /{id}/reject         | JWT  | ADMIN  | Reject payout             |
| POST   | /{id}/process        | JWT  | ADMIN  | Initiate bank transfer    |

---

## 10. Admin (`/api/v1/admin`)

| Method | Endpoint              | Auth | Roles | Description               |
|--------|-----------------------|------|-------|---------------------------|
| GET    | /dashboard            | JWT  | ADMIN | Dashboard metrics         |
| GET    | /users                | JWT  | ADMIN | List all users            |
| GET    | /farmers              | JWT  | ADMIN | List all farmers          |
| GET    | /farmers/{id}         | JWT  | ADMIN | Farmer detail with bank   |
| PUT    | /farmers/{id}/approve | JWT  | ADMIN | Approve farmer account    |
| PUT    | /farmers/{id}/reject  | JWT  | ADMIN | Reject farmer account     |
| GET    | /buyers               | JWT  | ADMIN | List all buyers           |
| GET    | /products             | JWT  | ADMIN | List all products (full)  |
| GET    | /orders               | JWT  | ADMIN | List all orders (full)    |

### GET /dashboard
```json
{
  "success": true,
  "data": {
    "total_orders": 1234,
    "total_sales_paise": 5678000,
    "total_quantity_sold": 45000,
    "total_farmer_payout_paise": 3456000,
    "total_platform_commission_paise": 2222000,
    "active_farmers": 56,
    "active_buyers": 123,
    "pending_payouts": 5,
    "completed_payouts": 890,
    "failed_payouts": 3,
    "pending_farmer_approvals": 2
  }
}
```

---

## 11. Reports (`/api/v1/reports`)

| Method | Endpoint              | Auth | Roles | Description               |
|--------|-----------------------|------|-------|---------------------------|
| GET    | /orders               | JWT  | ADMIN | Order report with filters |
| GET    | /payouts              | JWT  | ADMIN | Payout report             |
| GET    | /revenue              | JWT  | ADMIN | Revenue summary           |
| GET    | /export               | JWT  | ADMIN | Export report as CSV      |

### Query Parameters
- `date_from`, `date_to` — Custom date range
- `period` — `today|yesterday|week|month`
- `product_id`, `farmer_id`, `buyer_id` — Entity filters
- `status` — Order/payout status filter
- `page`, `limit` — Pagination

---

## 12. Webhooks (`/api/v1/webhooks`)

| Method | Endpoint              | Auth        | Description                |
|--------|-----------------------|-------------|----------------------------|
| POST   | /razorpay             | Signature   | Razorpay event webhook     |

> Webhook signature verified against `RAZORPAY_WEBHOOK_SECRET`. No JWT required.

---

## 13. Settings (`/api/v1/settings`)

| Method | Endpoint              | Auth | Roles | Description               |
|--------|-----------------------|------|-------|---------------------------|
| GET    | /languages            | No   | —     | Available languages       |
| GET    | /categories           | JWT  | Any   | Product categories        |
| GET    | /units                | JWT  | Any   | Available units           |
| GET    | /quality-grades       | JWT  | Any   | Quality grade options     |

---

## 14. Market Prices (`/api/v1/market-prices`)

Provides official Government of India AGMARKNET mandi market prices via `data.gov.in` (Resource: `9ef84268-d588-465a-a308-a864a43d0070`).
Supports live retrieval, caching to MongoDB, resilient offline fallback, and comprehensive filtering.

| Method | Endpoint                    | Auth | Roles | Description                                   |
|--------|-----------------------------|------|-------|-----------------------------------------------|
| GET    | `/`                         | No   | Any   | List mandi market prices with query filters   |
| GET    | `/latest`                   | No   | Any   | Get latest single mandi rate for a commodity  |
| GET    | `/filter-options`           | No   | Any   | Recommended commodities and district options  |

### Query Parameters for `GET /api/v1/market-prices`
- `commodity` (string, optional) — Filter by commodity (e.g., `Paddy`, `Tomato`, `Onion`)
- `state` (string, optional) — Filter by state (e.g., `Tamil Nadu`)
- `district` (string, optional) — Filter by district (e.g., `Madurai`)
- `market` (string, optional) — Filter by mandi market name
- `limit` (integer, default: 20, max: 100) — Pagination limit
- `offset` (integer, default: 0) — Pagination offset

### Example Request
```http
GET /api/v1/market-prices?commodity=Paddy&district=Madurai HTTP/1.1
Host: localhost:8000
Accept: application/json
```

### Example Response (Live Mandi Rates)
```json
{
  "success": true,
  "data": {
    "records": [
      {
        "price_id": "mp_paddy_madurai_2026-10-09",
        "commodity": "Paddy",
        "market": "Madurai",
        "state": "Tamil Nadu",
        "district": "Madurai",
        "variety": "Common",
        "grade": "FAQ",
        "min_price_paise": 220000,
        "max_price_paise": 260000,
        "modal_price_paise": 240000,
        "min_price_display": "₹2,200.00",
        "max_price_display": "₹2,600.00",
        "modal_price_display": "₹2,400.00",
        "price_per_kg_paise": 2400,
        "price_per_kg_display": "₹24.00 / kg",
        "unit": "Quintal",
        "arrival_date": "2026-10-09",
        "source": "data.gov.in AGMARKNET",
        "retrieved_at": "2026-10-09T06:30:00Z"
      }
    ],
    "count": 1,
    "live": true,
    "source": "data.gov.in AGMARKNET",
    "message": "Live government mandi rates retrieved successfully."
  },
  "error": null,
  "request_id": "req-9b84a1e"
}
```

### Example Response (Cached Fallback when Upstream Unreachable)
```json
{
  "success": true,
  "data": {
    "records": [
      {
        "price_id": "mp_paddy_madurai_2026-10-09",
        "commodity": "Paddy",
        "market": "Madurai",
        "state": "Tamil Nadu",
        "district": "Madurai",
        "variety": "Common",
        "grade": "FAQ",
        "min_price_paise": 220000,
        "max_price_paise": 260000,
        "modal_price_paise": 240000,
        "min_price_display": "₹2,200.00",
        "max_price_display": "₹2,600.00",
        "modal_price_display": "₹2,400.00",
        "price_per_kg_paise": 2400,
        "price_per_kg_display": "₹24.00 / kg",
        "unit": "Quintal",
        "arrival_date": "2026-10-09",
        "source": "data.gov.in AGMARKNET (Cached)",
        "retrieved_at": "2026-10-09T06:30:00Z"
      }
    ],
    "count": 1,
    "live": false,
    "source": "data.gov.in AGMARKNET (Cached)",
    "message": "Live government API unavailable (Government market API server is currently unreachable). Displaying cached mandi prices."
  },
  "error": null,
  "request_id": "req-9b84a1e"
}
```

---

## 15. Health

| Method | Endpoint    | Auth | Description           |
|--------|-------------|------|-----------------------|
| GET    | /health     | No   | Liveness check        |
| GET    | /health/ready| No  | Readiness (DB check)  |

---

## Error Codes

| Code                        | HTTP | Description                          |
|-----------------------------|------|--------------------------------------|
| VALIDATION_ERROR            | 422  | Request validation failed            |
| UNAUTHORIZED                | 401  | Missing/invalid token                |
| FORBIDDEN                   | 403  | Insufficient permissions             |
| NOT_FOUND                   | 404  | Resource not found                   |
| CONFLICT                    | 409  | Duplicate resource                   |
| PRODUCT_OUT_OF_STOCK        | 409  | Insufficient quantity                |
| OTP_EXPIRED                 | 400  | OTP has expired                      |
| OTP_INVALID                 | 400  | Invalid OTP code                     |
| OTP_MAX_ATTEMPTS            | 429  | Too many OTP attempts                |
| OTP_COOLDOWN                | 429  | OTP resend cooldown active           |
| PAYMENT_VERIFICATION_FAILED | 400  | Razorpay signature invalid           |
| PAYMENT_ALREADY_VERIFIED    | 409  | Payment already processed            |
| PAYOUT_NOT_ELIGIBLE         | 400  | Payout cannot be processed           |
| MARKET_PRICE_UNAVAILABLE    | 503  | Government price data unavailable    |
| EMAIL_ALREADY_EXISTS        | 409  | Email already registered             |
| PHONE_ALREADY_EXISTS        | 409  | Phone already registered             |
| FARMER_NOT_APPROVED         | 403  | Farmer account pending approval      |
| RATE_LIMIT_EXCEEDED         | 429  | Too many requests                    |
| INTERNAL_ERROR              | 500  | Internal server error                |
