# VayalConnect — Security Design

## 1. Authentication Security

### Password Storage
- **Algorithm**: bcrypt with work factor 12
- **Never**: Store plaintext passwords

### JWT Tokens
- **Access Token**: HS256, 30-minute expiry
- **Refresh Token**: 7-day expiry, stored hashed in DB
- **Rotation**: New refresh token on each refresh, old one revoked
- **Payload**: `{user_id, role, exp, iat, jti}`

### OTP Security
- **Generation**: `secrets.randbelow(900000) + 100000` (6-digit)
- **Storage**: bcrypt-hashed
- **Expiry**: 10 minutes (TTL index)
- **Max attempts**: 5 per OTP
- **Resend cooldown**: 60 seconds
- **Rate limit**: 5 OTP requests per hour per email

## 2. Authorization (RBAC)

### Enforcement Points
1. **Router Dependency**: Role check before handler execution
2. **Service Layer**: Business rule + ownership validation
3. **Repository Layer**: Query scoping by actor
4. **Response Schema**: Role-specific Pydantic models

### Access Matrix

| Resource              | FARMER      | BUYER       | ADMIN      |
|-----------------------|-------------|-------------|------------|
| Own profile           | R/W         | R/W         | R/W        |
| Own bank details      | R/W         | —           | R (admin)  |
| Other's bank details  | ✗           | ✗           | R          |
| Own products          | R/W/D       | —           | R/W/D      |
| Browse products       | —           | R           | R          |
| Product gov price     | ✗           | ✗           | R          |
| Product buyer price   | ✗           | R           | R          |
| Product farmer payout | R (own)     | ✗           | R          |
| Product commission    | ✗           | ✗           | R          |
| Create order          | ✗           | W           | W          |
| Own orders            | R (farmer)  | R (buyer)   | R (all)    |
| Order financials      | payout only | price only  | R (all)    |
| Own payouts           | R           | ✗           | R/W        |
| All payouts           | ✗           | ✗           | R/W        |
| Commission config     | ✗           | ✗           | R/W        |
| Market prices         | ✗           | ✗           | R          |
| Dashboard             | ✗           | ✗           | R          |
| Reports               | ✗           | ✗           | R          |
| User management       | ✗           | ✗           | R/W        |
| Audit logs            | ✗           | ✗           | R          |

## 3. Data Security

### Bank Details Encryption
- Encrypt at rest using Fernet symmetric encryption
- Encryption key stored in environment variables
- Never log full account numbers
- Mask in API responses: `XXXX1234`

### Response Filtering
- Separate Pydantic response models per role
- Never return raw MongoDB documents
- Financial fields stripped based on caller role

## 4. API Security

### Rate Limiting
| Endpoint Group | Limit              |
|----------------|--------------------| 
| Auth endpoints | 10 req/min/IP      |
| OTP requests   | 5 req/hour/email   |
| Payment verify | 10 req/min/user    |
| General API    | 100 req/min/user   |

### Input Validation
- All inputs validated via Pydantic strict schemas
- MongoDB injection: no raw `$` operators from user input
- Request size limits
- File upload size limits

### CORS
- Configurable allowed origins
- Credentials support for authenticated requests

## 5. Payment Security

### Razorpay Integration
- All keys in environment variables only
- Order amount calculated server-side only
- Never trust amount from client
- Signature verification mandatory
- Webhook signature verification
- Idempotency keys for all payment operations

### Financial Integrity
- Integer paise storage (no floating point)
- Consistency invariant enforced on every transaction
- Reconciliation utilities for admin

## 6. IDOR Prevention

Every resource access validates:
```python
if resource.owner_id != current_user.id and current_user.role != "ADMIN":
    raise ForbiddenException()
```

Tested scenarios:
- Farmer A accessing Farmer B's bank details → 403
- Buyer accessing farmer payout → 403  
- Farmer accessing buyer price → 403
- Buyer accessing another buyer's order → 404

## 7. Audit Trail

### Logged Events
- Authentication events (login, logout, failed attempts)
- Admin actions (approvals, rejections, commission changes)
- Financial events (orders, payments, payouts)
- Data modifications (profile updates, product changes)

### Never Logged
- Passwords, OTPs, API keys, secrets
- Full bank account numbers
- Payment card details
- Razorpay secrets

## 8. Idempotency

- Order creation: client-provided idempotency key
- Payment verification: razorpay_payment_id uniqueness
- Webhook processing: event ID deduplication
- Payout processing: payout_number uniqueness
