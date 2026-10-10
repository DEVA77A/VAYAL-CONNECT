# VayalConnect — Implementation Plan

## Phase-by-Phase Implementation Order

### Phase 1: Project Foundation ✅ (Architecture docs)
- [x] System architecture document
- [x] Database design document
- [x] API specification document
- [x] Security design document
- [x] Implementation plan

### Phase 2: Project Scaffolding
- [ ] Project directory structure
- [ ] requirements.txt
- [ ] .env.example
- [ ] Dockerfile
- [ ] render.yaml
- [ ] .gitignore

### Phase 3: Core Infrastructure
- [ ] config.py (Pydantic BaseSettings)
- [ ] database.py (Motor async MongoDB connection)
- [ ] security.py (JWT + bcrypt)
- [ ] exceptions.py (error hierarchy)
- [ ] logging_config.py
- [ ] main.py (FastAPI app)
- [ ] Health endpoints

### Phase 4: Models & Schemas
- [ ] All MongoDB document models
- [ ] All Pydantic request/response schemas
- [ ] Role-specific response schemas
- [ ] Money utility (paise conversion)

### Phase 5: Authentication & OTP
- [ ] User repository
- [ ] Auth service
- [ ] OTP service
- [ ] Brevo email integration
- [ ] Auth router (register, login, OTP, refresh)
- [ ] Rate limiting middleware
- [ ] Request ID middleware

### Phase 6: RBAC
- [ ] Role dependency injection
- [ ] Ownership check utilities
- [ ] API deps (get_current_user, require_role)

### Phase 7: Farmer & Buyer Modules
- [ ] Farmer profile repository
- [ ] Buyer profile repository
- [ ] Farmer router (profile, bank details)
- [ ] Buyer router (profile)
- [ ] Bank detail encryption
- [ ] Role selection endpoint

### Phase 8: Government Market Price
- [ ] MarketPriceProvider abstraction
- [ ] GovernmentMarketPriceProvider (data.gov.in)
- [ ] Market price caching
- [ ] Market price repository
- [ ] Admin market price router

### Phase 9: Pricing Engine
- [ ] PricingPolicy model
- [ ] CommissionConfig model
- [ ] PricingEngine service
- [ ] PricingSnapshot creation
- [ ] Commission service
- [ ] Pricing repository
- [ ] Admin pricing/commission router

### Phase 10: Product Module
- [ ] Product repository
- [ ] Product service (with pricing integration)
- [ ] Product router (create, list, detail)
- [ ] Role-filtered product responses
- [ ] Image URL handling

### Phase 11: Order & Inventory
- [ ] Order repository
- [ ] Order service
- [ ] Atomic inventory reservation
- [ ] Order state machine
- [ ] Order router
- [ ] Idempotency key handling

### Phase 12: Razorpay Payments
- [ ] Razorpay integration
- [ ] Payment service
- [ ] Payment repository
- [ ] Payment verification
- [ ] Webhook handler
- [ ] Webhook signature verification

### Phase 13: Farmer Payout
- [ ] PayoutProvider abstraction
- [ ] RazorpayPayoutProvider
- [ ] SandboxPayoutProvider
- [ ] Payout service
- [ ] Payout repository
- [ ] Admin payout approval workflow
- [ ] Payout router

### Phase 14: Admin Dashboard & Reports
- [ ] Admin service
- [ ] Report service (MongoDB aggregation)
- [ ] Admin router
- [ ] Report router
- [ ] Dashboard metrics
- [ ] Report filters

### Phase 15: Audit Logging
- [ ] Audit service
- [ ] Audit repository
- [ ] Audit decorator/middleware

### Phase 16: Testing
- [ ] Auth tests
- [ ] RBAC tests
- [ ] Pricing tests
- [ ] Order tests
- [ ] Payment tests
- [ ] Payout tests
- [ ] Admin tests
- [ ] Security/IDOR tests

### Phase 17: Documentation & Deployment
- [ ] README.md
- [ ] payment-flow.md
- [ ] pricing-engine.md
- [ ] deployment.md
- [ ] Seed scripts

## Dependency Graph

```
Core Config → Database → Models/Schemas → Repositories
                                              ↓
Auth Service → OTP/Brevo → RBAC Dependencies
                              ↓
Market Price Provider → Pricing Engine → Commission Service
                              ↓
Product Service → Order Service → Payment Service → Payout Service
                                       ↓
                              Admin Service → Report Service → Audit Service
```

## External Dependencies Requiring Manual Setup

1. **MongoDB Atlas**: Create cluster, get connection string
2. **Brevo**: Create account, get API key, verify sender email
3. **data.gov.in**: Register, get API key for AGMARKNET dataset
4. **Razorpay**: Create test account, get key_id and key_secret
5. **Render**: Create account for deployment
