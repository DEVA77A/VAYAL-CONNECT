# VayalConnect — Deployment Guide

## 1. Prerequisites & Services

1. **MongoDB Atlas**:
   - Connection string: `mongodb+srv://<user>:<password>@cluster0.mongodb.net/?retryWrites=true&w=majority`
   - Database name: `vayalconnect`
2. **Brevo (Sendinblue)**:
   - API Key for transactional email OTP delivery
3. **Razorpay**:
   - Key ID & Secret for payments
   - Webhook Secret for signature validation
   - RazorpayX Account for fund transfers
4. **Data.gov.in**:
   - API key for AGMARKNET agricultural market price datasets

---

## 2. Environment Variables

Create `.env` based on `.env.example`:

```bash
cp .env.example .env
```

Ensure `JWT_SECRET` and `ENCRYPTION_KEY` are generated using secure random keys:

```python
from cryptography.fernet import Fernet
import secrets

print("JWT_SECRET:", secrets.token_urlsafe(32))
print("ENCRYPTION_KEY:", Fernet.generate_key().decode())
```

---

## 3. Database Initialization & Admin Seeding

Run the seed script to create initial indexes, default pricing policies, and the primary admin account:

```bash
python -m scripts.seed_admin
```

---

## 4. Running Locally

```bash
uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000 --reload
```

Interactive API documentation available at:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

---

## 5. Docker Deployment

Build container image:

```bash
docker build -t vayalconnect-backend .
```

Run container:

```bash
docker run -p 8000:8000 --env-file .env vayalconnect-backend
```

---

## 6. Render Deployment

The repository includes a ready-to-use `render.yaml` configuration for zero-friction deployment to Render. Simply connect the repository to Render Web Service and configure environment secrets.
