# 🌾 VayalConnect Flutter Mobile Application

Cross-platform mobile application for **VayalConnect** (நம்ம வயல், நேரடி CONNECT), an agricultural marketplace connecting farmers and buyers with transparent, government-referenced mandi rates.

---

## 🎯 Architecture & Data Flow

```
+-------------------------------------------------------+
|                VayalConnect Flutter App                |
|             (MarketPricesScreen / Widgets)            |
+-------------------------------------------------------+
                           │
                           ▼ (HTTP GET /api/v1/market-prices)
+-------------------------------------------------------+
|             FastAPI Backend (VayalConnect)            |
|        - Reads GOVERNMENT_MARKET_API_KEY from .env     |
|        - Normalizes Quintal & KG pricing              |
|        - Caches to MongoDB for resilient fallback     |
+-------------------------------------------------------+
                           │
                           ▼ (HTTPS Authenticated Request)
+-------------------------------------------------------+
|          data.gov.in AGMARKNET Mandi API              |
|   (Resource: 9ef84268-d588-465a-a308-a864a43d0070)    |
+-------------------------------------------------------+
```

### 🔒 Security Principles
- **No API Keys in App**: The Flutter mobile client holds **zero** government API keys or secrets.
- **Backend Mediation**: All external government data is routed through the FastAPI backend (`vayalconnect-backend`).
- **Resilient Fallback**: If the government server is unreachable or times out, the backend gracefully provides cached historical mandi rates with an explicit indicator.

---

## 📁 Project Structure

```
vayalconnect-flutter/
├── pubspec.yaml                 # Dependencies (http, intl, flutter)
├── lib/
│   ├── main.dart                # Application entry point
│   ├── config/
│   │   └── api_config.dart      # FastAPI base URL configuration
│   ├── models/
│   │   └── market_price.dart    # MarketPriceItem, ListResponse, FilterOptions
│   ├── services/
│   │   └── market_price_service.dart # HTTP client communicating with backend
│   ├── theme/
│   │   └── app_theme.dart       # Agriculture green palette & styling
│   ├── widgets/
│   │   ├── market_price_card.dart  # Mandi rate card with quintal & kg prices
│   │   └── state_views.dart        # Loading, error, empty, and status views
│   └── screens/
│       └── market_prices_screen.dart # Main screen with filters, search, pull-to-refresh
└── test/
    ├── market_price_model_test.dart
    ├── market_price_service_test.dart
    └── widget_test.dart
```

---

## 🚀 How to Run

### 1. Start the FastAPI Backend
```bash
cd "c:\VAYAL CONNECT\vayalconnect-backend"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Configure Backend Host (if needed)
In `lib/config/api_config.dart`:
- **Android Emulator**: `http://10.0.2.2:8000` (default)
- **Physical Device**: `http://<YOUR_LAN_IP>:8000`
- **Desktop / Web**: `http://localhost:8000`

### 3. Run the Flutter App
```bash
cd "c:\VAYAL CONNECT\vayalconnect-flutter"
flutter pub get
flutter run
```

---

## 🧪 Running Automated Tests
```bash
flutter test
```
