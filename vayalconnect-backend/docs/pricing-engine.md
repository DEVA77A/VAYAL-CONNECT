# VayalConnect — Dynamic Pricing Engine

The Pricing Engine is the central financial authority in VayalConnect. It prevents price manipulation, incorporates real-time Government Agricultural Market prices (AGMARKNET / data.gov.in), applies platform commission policies, and guarantees fair farmer payouts.

---

## 1. Principles

1. **Zero Client Trust**: Android clients never specify or compute prices. Prices are computed entirely by the backend upon product creation and frozen into an immutable `pricing_snapshot`.
2. **Deterministic Formula**:
   $$\text{Farmer Payout} = \text{Gov Market Ref Price} \times \text{Farmer Payout \% (BPS)}$$
   $$\text{Buyer Price} = \text{Gov Market Ref Price} \times \text{Buyer Price \% (BPS)}$$
   $$\text{Platform Commission} = \text{Buyer Price} - \text{Farmer Payout}$$
3. **Basis Points (BPS)**: Percentages are expressed in integer basis points (`1% = 100 bps`):
   - Default Farmer Payout: `7000 bps` (70%)
   - Default Buyer Price: `9000 bps` (90%)
   - Default Platform Commission: `2000 bps` (20%)
4. **Unit Conversion**:
   AGMARKNET publishes modal prices in ₹ per Quintal (100 kg). The engine automatically normalizes prices to per-Kilogram / target units.

---

## 2. Immutable Pricing Snapshots

When a farmer lists a product:
1. Backend queries Government AGMARKNET API for the specific crop & market.
2. If real-time API is unreachable or cached, the engine falls back to the most recent cached modal price.
3. The engine creates an immutable `pricing_snapshot` record:
   ```json
   {
     "snapshot_id": "snap_673...",
     "product_id": "prod_673...",
     "government_reference_price_paise": 300000,
     "government_per_kg_paise": 3000,
     "farmer_payout_per_unit_paise": 2100,
     "buyer_price_per_unit_paise": 2700,
     "commission_per_unit_paise": 600,
     "commission_percentage_bps": 2000,
     "pricing_policy_version": 1,
     "created_at": "2026-10-09T00:00:00Z"
   }
   ```
4. Future changes to platform commission or fluctuating government market prices do **NOT** retroactively mutate existing listed batches or pending orders.

---

## 3. Role-Based Information Segregation (IDOR Prevention)

| Data Field | Farmer | Buyer | Admin |
| :--- | :---: | :---: | :---: |
| Farmer Guaranteed Payout | ✅ | ❌ | ✅ |
| Buyer Retail Price | ❌ | ✅ | ✅ |
| Platform Commission | ❌ | ❌ | ✅ |
| Government Reference Modal Price | ❌ | ❌ | ✅ |
| Bank Account Details (Encrypted) | ✅ (Masked) | ❌ | ✅ (Audited) |
