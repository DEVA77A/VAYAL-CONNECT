# 🌾 VayalConnect Backend

> Secure, production-ready agricultural marketplace backend connecting Farmers, Buyers, and Platform Admins.

Current market-price workflow and deployment gates: [Tamil Nadu statewide reference prices](docs/STATEWIDE_MARKET_PRICES.md).

---

## 🌟 Key Features

- **Strict Role-Based Access Control (RBAC)**: Enforced separation between `FARMER`, `BUYER`, and `ADMIN`.
- **Market reference cache**: One consolidated Groq request over validated retrieved evidence; farmer selling prices remain independent. See [configuration, verification and daily scheduling](docs/GROQ_MARKET_PRICES.md).
- **Role-Filtered Response Payloads**: Farmers see guaranteed payouts only; Buyers see retail prices only; Admins see comprehensive margin breakdowns.
- **Secure Authentication & Brevo OTP**: Cryptographic password hashing (bcrypt), Fernet bank encryption, and rate-limited email OTPs.
- **Razorpay TEST checkout**: Server-owned amounts, signature plus gateway capture verification, idempotent payment state, and payout review. Bank transfers are disabled; no simulated transfer is treated as paid.
- **Bilingual Localization Support**: English (`en`) and Tamil (`ta`).
- **Audit Logging**: Comprehensive trace logging of all critical financial, authentication, and status transitions.

---

## 📂 Project Structure

```
vayalconnect-backend/
├── app/
│   ├── api/             # FastAPI API routers & dependencies
│   ├── core/            # Configuration, database, security, exceptions
│   ├── integrations/    # Brevo, Razorpay, data.gov.in AGMARKNET
│   ├── middleware/      # Rate limiting, request ID tracking
│   ├── repositories/    # MongoDB async database operations
│   ├── schemas/         # Pydantic schemas (common, auth, product, order, etc.)
│   ├── services/        # Business logic (pricing engine, order, auth, payment)
│   └── utils/           # Money utilities (integer paise math)
├── docs/                # Architecture, API specs, database schema, payment & pricing guides
├── scripts/             # Seed scripts (seed_admin.py)
├── tests/               # Pytest test suite (auth, rbac, idor, money, pricing, orders, payments)
├── Dockerfile
├── render.yaml
└── requirements.txt
```

---

## 🚀 Quick Start

### 1. Install Dependencies
```bash
pip install -r requirements.txt
```

### 2. Configure Environment
```bash
cp .env.example .env
```

### 3. Run Test Suite
```bash
pytest tests/
```

### 4. Start Server
```bash
uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000 --reload
```

## Operations and release verification

See [RELEASE_GUIDE.md](../RELEASE_GUIDE.md) for private administrator provisioning, coordinated key rotation, financial definitions, deployment gates and Android signing. Source tests do not establish external payment or government API availability.
