# VayalConnect — System Architecture

## வயல் Connect | நம்ம வயல், நேரடி CONNECT

---

## 1. System Overview

VayalConnect is a secure agricultural marketplace connecting **Farmers**, **Buyers**, and **Admin**.
The backend is a Python FastAPI application with MongoDB Atlas, serving a mobile (Android) frontend.

```
┌─────────────────────────────────────────────────────────────────┐
│                     MOBILE APPLICATION                          │
│               (Android / Flutter — built separately)            │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS REST API
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                   FASTAPI BACKEND (Render)                       │
│                                                                 │
│  ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌──────────────────┐  │
│  │   Auth   │ │   RBAC   │ │ Middleware │ │  Rate Limiting   │  │
│  └──────────┘ └──────────┘ └───────────┘ └──────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     API v1 Routers                       │   │
│  │  auth │ farmers │ buyers │ products │ orders │ payments  │   │
│  │  payouts │ admin │ reports │ settings │ webhooks          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     Service Layer                        │   │
│  │  AuthService │ OTPService │ PricingService │ OrderService│   │
│  │  PaymentService │ PayoutService │ ReportService          │   │
│  │  CommissionService │ AuditService │ MarketPriceService   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Repository Layer                       │   │
│  │  UserRepo │ FarmerRepo │ BuyerRepo │ ProductRepo         │   │
│  │  OrderRepo │ PaymentRepo │ PayoutRepo │ PricingRepo      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Integration Layer                       │   │
│  │  Brevo │ GovernmentMarketAPI │ Razorpay │ MediaStorage   │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
   │ MongoDB Atlas │ │   Razorpay   │ │    Brevo     │
   └──────────────┘ └──────────────┘ └──────────────┘
```

## 2. Technology Stack

| Component          | Technology                                   |
|--------------------|----------------------------------------------|
| Language           | Python 3.11+                                 |
| Framework          | FastAPI                                      |
| Database           | MongoDB Atlas (Motor async driver)           |
| Validation         | Pydantic v2                                  |
| Authentication     | JWT (python-jose), bcrypt                    |
| Email OTP          | Brevo (sib-api-v3-sdk)                       |
| Market Prices      | data.gov.in AGMARKNET API                    |
| Payments           | Razorpay Python SDK                          |
| Deployment         | Render (Docker)                              |
| Financial Math     | Python Decimal / integer paise               |

## 3. Component Responsibilities

### 3.1 Core Layer (`app/core/`)
- **config.py** — Environment-based settings via Pydantic BaseSettings
- **security.py** — JWT creation/validation, password hashing (bcrypt)
- **database.py** — MongoDB Atlas connection via Motor (async)
- **exceptions.py** — Application-wide exception hierarchy
- **logging_config.py** — Structured logging (no secrets)

### 3.2 API Layer (`app/api/v1/`)
- Versioned REST routers, each tagged for OpenAPI
- Request validation via Pydantic schemas
- Role-specific response filtering
- Dependency injection for auth/RBAC

### 3.3 Service Layer (`app/services/`)
- All business logic lives here
- Services orchestrate repositories, integrations, and pricing
- No direct MongoDB access — always through repositories

### 3.4 Repository Layer (`app/repositories/`)
- Data access abstraction over MongoDB collections
- Atomic operations for inventory
- Index management
- Ownership-scoped queries

### 3.5 Integration Layer (`app/integrations/`)
- Provider pattern for all external services
- Abstract base + concrete implementation
- Testable via mock providers

### 3.6 Middleware (`app/middleware/`)
- Request ID injection
- CORS
- Rate limiting
- Security headers

## 4. Authentication & Authorization Flow

```
Mobile App                    Backend
    │                           │
    │──── POST /auth/register ──▶│ Validate → Hash password → Store user
    │                           │ → Send OTP via Brevo → Return success
    │                           │
    │──── POST /auth/verify-otp─▶│ Validate OTP → Mark email verified
    │                           │
    │──── POST /auth/select-role▶│ Assign FARMER/BUYER role → Create profile
    │                           │
    │──── POST /auth/login ─────▶│ Validate credentials → Issue JWT pair
    │                           │
    │──── Protected Request ────▶│ Validate JWT → Check role → Check ownership
    │     (Authorization header) │ → Process or 403
```

### JWT Structure
- **Access Token**: 30 min expiry, contains user_id + role
- **Refresh Token**: 7 days, stored in DB, rotatable

### RBAC Enforcement
- **Router level**: FastAPI dependencies check role
- **Service level**: Ownership validation
- **Repository level**: Scoped queries (farmer_id filter)
- **Response level**: Role-specific Pydantic schemas

## 5. Pricing Engine Architecture

```
Government Market Price API
         │
         ▼
┌─────────────────────┐
│ MarketPriceProvider  │
│ (data.gov.in)       │
└────────┬────────────┘
         │ reference_price
         ▼
┌─────────────────────┐     ┌──────────────────┐
│   PricingEngine     │◄────│ CommissionConfig  │
│                     │     │ (Admin-managed)   │
│ Input:              │     └──────────────────┘
│  - product          │
│  - quantity          │
│  - unit             │
│  - quality          │
│  - location         │
│  - gov_ref_price    │
│                     │
│ Output:             │
│  - farmer_payout    │
│  - buyer_price      │
│  - commission       │
│  - snapshot         │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  PricingSnapshot    │
│  (Immutable)        │
│                     │
│  Stored with order  │
│  NEVER recalculated │
└─────────────────────┘
```

### Pricing Policy Model
- `PricingPolicy`: Defines how farmer_payout & buyer_price derive from gov_ref_price
- `CommissionConfig`: Admin-configurable commission percentage
- `PricingSnapshot`: Frozen record of all prices at transaction time

### Financial Safety
- All money stored as **integer paise** (₹35.50 = 3550)
- Python `Decimal` used for intermediate calculations
- Consistency invariant: `buyer_total == farmer_payout + platform_commission`
- Rounding uses ROUND_HALF_UP, applied once at final step

## 6. Order & Payment Flow

```
Buyer (Mobile)              Backend                    Razorpay
     │                        │                          │
     │─ POST /orders ────────▶│                          │
     │  {product_id, qty}     │ Validate stock           │
     │                        │ Atomic reserve qty       │
     │                        │ Calculate total (stored  │
     │                        │   buyer_price × qty)     │
     │                        │ Create order (PENDING)   │
     │                        │                          │
     │                        │── Create Razorpay Order ▶│
     │◀── {rz_order_id} ─────│◀── {order_id, amount} ──│
     │                        │                          │
     │── Razorpay Checkout ──────────────────────────────▶│
     │◀── {payment_id, sig} ─────────────────────────────│
     │                        │                          │
     │─ POST /payments/verify▶│                          │
     │  {order_id, payment_id,│ Verify signature         │
     │   signature}           │ Mark order PAID          │
     │                        │ Create payout record     │
     │◀── {confirmation} ────│                          │
```

### Inventory Concurrency
- MongoDB `find_one_and_update` with `{available_qty: {$gte: requested_qty}}`
- Atomic decrement prevents overselling
- Failed payments restore reserved quantity

## 7. Farmer Payout Flow

```
Order COMPLETED
      │
      ▼
Payout created (PENDING_APPROVAL)
      │
      ▼
Admin reviews
      │
      ├── APPROVE ──▶ APPROVED ──▶ PROCESSING ──▶ PAID
      │                                    │
      │                                    └──▶ FAILED
      │
      └── REJECT ───▶ REJECTED
```

### Payout Provider Abstraction
```python
class PayoutProvider(ABC):
    async def initiate_payout(self, payout: PayoutRequest) -> PayoutResult
    async def check_payout_status(self, reference_id: str) -> PayoutStatus

class RazorpayPayoutProvider(PayoutProvider): ...
class SandboxPayoutProvider(PayoutProvider): ...  # For testing
```

## 8. Security Architecture

### Defense Layers
1. **Transport**: HTTPS (Render TLS)
2. **Authentication**: JWT with expiry + refresh rotation
3. **Authorization**: Role-based + resource ownership
4. **Input Validation**: Pydantic strict schemas
5. **Rate Limiting**: Auth/OTP/payment endpoints
6. **Financial**: Server-calculated prices, signature verification
7. **Data**: Role-filtered responses, encrypted bank details
8. **Audit**: Immutable action log
9. **Secrets**: Environment variables only

### IDOR Prevention
- Every resource access checks `actor_id == resource.owner_id`
- Bank details: only accessible by owning farmer
- Orders: only accessible by involved buyer/farmer
- Payouts: only accessible by receiving farmer + admin

## 9. Deployment Architecture

```
┌──────────────────────────────┐
│          Render               │
│                              │
│  ┌────────────────────────┐  │
│  │  Docker Container      │  │
│  │  uvicorn app.main:app  │  │
│  │  --host 0.0.0.0        │  │
│  │  --port $PORT          │  │
│  └───────────┬────────────┘  │
│              │               │
│  Environment Variables:      │
│  MONGODB_URI, JWT_SECRET,    │
│  BREVO_API_KEY, RAZORPAY_*   │
└──────────────┬───────────────┘
               │
    ┌──────────┴──────────┐
    ▼                     ▼
MongoDB Atlas        External APIs
```

### Health Checks
- `GET /health` — Basic liveness
- `GET /health/ready` — MongoDB connectivity check
