# 🌾 VayalConnect Backend

> Secure, production-ready agricultural marketplace backend connecting Farmers, Buyers, and Platform Admins.

---

## 🌟 Key Features

- **Strict Role-Based Access Control (RBAC)**: Enforced separation between `FARMER`, `BUYER`, and `ADMIN`.
- **Zero-Trust Pricing Engine**: Server-calculated prices integrating Government Market Price API (`data.gov.in AGMARKNET`).
- **Role-Filtered Response Payloads**: Farmers see guaranteed payouts only; Buyers see retail prices only; Admins see comprehensive margin breakdowns.
- **Secure Authentication & Brevo OTP**: Cryptographic password hashing (bcrypt), Fernet bank encryption, and rate-limited email OTPs.
- **Full Razorpay Integration**: Order creation, HMAC-SHA256 signature verification, webhook processing, and admin-approved farmer payouts.
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
