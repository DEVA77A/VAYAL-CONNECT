"""Synthetic observations only: tests never establish real crop/source coverage."""

import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.integrations.market_evidence import (
    SourceQuote,
    MarketEvidenceRetriever,
    OGD_URL,
    IST,
)
from app.integrations.statewide_market import (
    aggregate,
    matches,
    StatewideMarketProvider,
    statewide_query,
)
from app.services.market_discovery import MarketDiscoveryService


def observations(
    commodity="Synthetic crop",
    unit="quintal",
    prices=(10000, 20000, 90000),
    variety="Local",
    **changes,
):
    return [
        SourceQuote.model_validate_json(
            json.dumps(
                {
                    "commodity": commodity,
                    "unit": unit,
                    "price_paise": price,
                    "modal_price_paise": price,
                    "market": f"Synthetic market {i}",
                    "district": "Synthetic district",
                    "state": "Tamil Nadu",
                    "currency": "INR",
                    "observation_date": datetime.now(IST).date().isoformat(),
                    "source": "Synthetic OGD fixture",
                    "source_url": OGD_URL,
                    "variety": variety,
                    **changes,
                }
            ),
            context={"history": True},
        )
        for i, price in enumerate(prices)
    ]


def reference_fixture(
    commodity="Paddy",
    category="Grains",
    unit="quintal",
    price=300000,
    stamp=None,
    observed=None,
    variety=None,
):
    quotes = observations(
        commodity,
        unit,
        (price,) * 3,
        variety,
        **({"observation_date": observed} if observed else {}),
    )
    return aggregate(
        quotes,
        [{"commodity": commodity, "category": category}],
        stamp or datetime.now(timezone.utc),
        history=True,
    )[0]


def test_median_distinct_markets_provenance_and_tamper_rejection():
    quotes = observations(prices=(10000, 20000, 90000, 40000))
    records = aggregate(
        quotes + quotes, [{"commodity": "Synthetic crop"}], datetime.now(timezone.utc)
    )
    assert len(records) == 1
    r = records[0]
    assert r["price_paise"] == 30000 and r["observation_count"] == 4
    assert len(r["source_records"]) == 4 and len(set(r["evidence_ids"])) == 4
    assert r["observation_dates"] == [datetime.now(IST).date().isoformat()]
    assert matches(r) and not matches({**r, "price_paise": 123})
    assert not matches({**r, "observation_count": 500})
    assert not matches(r, commodity="Unrelated") and not matches(r, state="Kerala")
    assert matches(r, market="civai")  # Statewide reference needs no farmer market.


def test_even_median_half_paise_rounding_and_unit_aliases():
    quotes = observations(prices=(1, 2, 3, 4), unit="kilogram")
    r = aggregate(
        quotes, [{"commodity": "Synthetic crop"}], datetime.now(timezone.utc)
    )[0]
    assert r["price_paise"] == 3 and r["unit"] == "kg"
    assert all(q["unit"] == "kilogram" for q in r["source_records"])
    assert matches(r)


def test_grade_and_source_groups_are_not_blended():
    quotes = observations(prices=(1, 2), grade="A") + observations(
        prices=(3, 4), grade="B"
    )
    assert not aggregate(
        quotes, [{"commodity": "Synthetic crop"}], datetime.now(timezone.utc)
    )
    unofficial = observations(source_url="https://example.org/unapproved")
    assert not aggregate(
        unofficial, [{"commodity": "Synthetic crop"}], datetime.now(timezone.utc)
    )


@pytest.mark.parametrize(
    "quotes", [[], observations(prices=(1,)), observations(prices=(1, 2))]
)
def test_insufficient_observations(quotes):
    assert (
        aggregate(quotes, [{"commodity": "Synthetic crop"}], datetime.now(timezone.utc))
        == []
    )


def test_group_units_varieties_grades_dates_and_states_separately():
    quotes = observations() + observations(unit="bunch") + observations(variety="Other")
    quotes += observations(state="Kerala")
    records = aggregate(
        quotes, [{"commodity": "Synthetic crop"}], datetime.now(timezone.utc)
    )
    assert len(records) == 3
    assert {(r["unit"], r["variety"]) for r in records} == {
        ("quintal", "Local"),
        ("bunch", "Local"),
        ("quintal", "Other"),
    }
    assert (
        len(
            aggregate(
                quotes,
                [{"commodity": "Synthetic crop", "variety": "Other"}],
                datetime.now(timezone.utc),
            )
        )
        == 1
    )
    yesterday = observations(
        observation_date=(datetime.now(IST).date() - timedelta(days=1)).isoformat()
    )
    assert not aggregate(
        yesterday, [{"commodity": "Synthetic crop"}], datetime.now(timezone.utc)
    )
    stale = aggregate(
        yesterday,
        [{"commodity": "Synthetic crop"}],
        datetime.now(timezone.utc),
        history=True,
    )[0]
    assert matches(stale) and stale["stale"]


def test_conflicting_market_cannot_inflate_count():
    quotes = observations()
    conflict = quotes[0].model_copy(
        update={"price_paise": 999, "modal_price_paise": 999}
    )
    assert not aggregate(
        quotes + [conflict],
        [{"commodity": "Synthetic crop"}],
        datetime.now(timezone.utc),
    )


def test_tamil_english_new_categories_and_no_location_required():
    query = {
        "commodity": "மல்லிகை",
        "category": "New flowers",
        "aliases": ["Jasmine"],
        "market": "civai",
    }
    row = aggregate(
        observations("Jasmine", "bunch"), [query], datetime.now(timezone.utc)
    )[0]
    assert row["category"] == "New flowers" and row["commodity"] == "மல்லிகை"
    assert row["unit"] == "bunch" and matches(row, commodity="Jasmine")
    assert not aggregate(
        observations("Rose", "bunch"), [query], datetime.now(timezone.utc)
    )


@pytest.mark.parametrize(
    "field,value",
    [
        ("price_paise", 0),
        ("price_paise", -1),
        ("price_paise", float("nan")),
        ("price_paise", float("inf")),
        ("price_paise", "bad"),
        ("unit", "basket"),
        ("unit", None),
        ("currency", "USD"),
        ("observation_date", None),
        ("source_url", None),
    ],
)
def test_invalid_values_cannot_be_aggregated(field, value):
    raw = observations()[0].model_dump(mode="json") | {field: value}
    with pytest.raises(ValueError):
        SourceQuote.model_validate_json(json.dumps(raw))


@pytest.fixture
def enabled(monkeypatch):
    monkeypatch.setattr(settings, "MARKET_STATEWIDE_ENABLED", True)
    monkeypatch.setattr(settings, "MARKET_SOURCE_VERIFIED", True)
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "synthetic-key")


@pytest.mark.asyncio
async def test_complete_batch_deterministic_zero_groq(enabled):
    queries = [
        {"commodity": "Jasmine", "category": "Flowers"},
        {"commodity": "Novel crop", "category": "New category"},
    ]
    retriever = SimpleNamespace(
        retrieve=AsyncMock(
            return_value=(
                observations("Jasmine", "bunch") + observations("Novel crop"),
                [],
            )
        )
    )
    with patch(
        "app.integrations.groq_market.GroqMarketProvider._discover", AsyncMock()
    ) as groq:
        result = await StatewideMarketProvider(retriever).discover_daily(queries)
    assert result["groq_requests"] == 0 and len(result["records"]) == 2
    assert len(result["observations"]) == 6
    retriever.retrieve.assert_awaited_once_with(
        [statewide_query(q) for q in queries], primary_only=True
    )
    groq.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("flag", ["MARKET_STATEWIDE_ENABLED", "MARKET_SOURCE_VERIFIED"])
async def test_gates_no_retrieval_or_ai(enabled, monkeypatch, flag):
    monkeypatch.setattr(settings, flag, "" if flag.endswith("KEY") else False)
    retriever = SimpleNamespace(retrieve=AsyncMock())
    result = await StatewideMarketProvider(retriever).discover_daily(
        [{"commodity": "Crop"}]
    )
    assert not result["records"] and result["groq_requests"] == 0
    retriever.retrieve.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["OGD_SOURCE_UNAVAILABLE", "SOURCE_ROW_LIMIT"])
async def test_partial_source_must_not_aggregate(enabled, failure):
    retriever = SimpleNamespace(
        retrieve=AsyncMock(return_value=(observations(), [failure]))
    )
    r = await StatewideMarketProvider(retriever).discover_daily(
        [{"commodity": "Synthetic crop"}]
    )
    assert (
        r["error_code"] == "SOURCE_INCOMPLETE"
        and not r["records"]
        and not r["observations"]
    )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure", [401, 403, 429, "timeout", "connection", "malformed", "empty", "changed"]
)
async def test_official_failures_are_bounded_no_prices(enabled, failure):
    calls = []

    def respond(request):
        calls.append(request)
        if isinstance(failure, int):
            return httpx.Response(failure, json={"error": "private"})
        if failure == "timeout":
            raise httpx.ReadTimeout("private", request=request)
        if failure == "connection":
            raise httpx.ConnectError("private", request=request)
        if failure == "malformed":
            return httpx.Response(200, content=b"{bad")
        return httpx.Response(
            200,
            json={}
            if failure == "changed"
            else {"status": "ok", "total": 0, "records": []},
        )

    original = httpx.AsyncClient
    with patch(
        "httpx.AsyncClient",
        side_effect=lambda **kwargs: original(
            transport=httpx.MockTransport(respond), timeout=1
        ),
    ):
        result = await StatewideMarketProvider(
            MarketEvidenceRetriever()
        ).discover_daily([{"commodity": "Synthetic crop"}])
    assert len(calls) == 1 and not result["records"] and result["groq_requests"] == 0
    assert "private" not in json.dumps(result)


@pytest.mark.asyncio
async def test_official_pagination_tn_filter_and_actual_parser(enabled):
    calls = []

    def respond(request):
        calls.append(request)
        assert request.url.params["filters[state]"] == "Tamil Nadu"
        offset = int(request.url.params["offset"])
        row = {
            "commodity": "Synthetic crop",
            "market": f"Market {offset}",
            "district": "Madurai",
            "state": "Tamil Nadu",
            "arrival_date": datetime.now(IST).strftime("%d/%m/%Y"),
            "unit": "Quintal",
            "modal_price": "200",
            "min_price": "100",
            "max_price": "300",
        }
        rows = [row, {**row, "currency": "USD"}] if offset == 0 else [row]
        return httpx.Response(200, json={"status": "ok", "total": 4, "records": rows})

    original = httpx.AsyncClient
    with patch(
        "httpx.AsyncClient",
        side_effect=lambda **kwargs: original(
            transport=httpx.MockTransport(respond), timeout=1
        ),
    ):
        result = await StatewideMarketProvider(
            MarketEvidenceRetriever()
        ).discover_daily([{"commodity": "Synthetic crop"}])
    assert len(calls) == 3 and result["records"][0]["price_paise"] == 20000
    assert (
        "OGD_ROW_REJECTED" in result["diagnostics"] and len(result["observations"]) == 3
    )
    assert all(
        q["original_unit"] == "Quintal" for q in result["records"][0]["source_records"]
    )


@pytest.mark.asyncio
async def test_cached_statewide_get_no_upstream_and_no_market_required():
    from app.main import app
    from app.core.database import get_database

    row = reference_fixture()
    db = MagicMock()
    app.dependency_overrides[get_database] = lambda: db
    try:
        with (
            patch(
                "app.repositories.pricing.PricingRepository.list_market_prices",
                AsyncMock(return_value=[row]),
            ) as reads,
            patch(
                "app.integrations.statewide_market.StatewideMarketProvider.discover_daily",
                AsyncMock(),
            ) as discovery,
        ):
            r = TestClient(app).get(
                "/api/v1/market-prices?commodity=Paddy&scope=statewide"
            )
        assert (
            r.status_code == 200
            and r.json()["data"]["records"][0]["observation_count"] == 3
        )
        assert reads.call_args.kwargs["scope"] == "statewide"
        discovery.assert_not_awaited()
    finally:
        app.dependency_overrides.pop(get_database, None)


@pytest.mark.asyncio
async def test_farmer_listing_selects_compatible_group_without_changing_selling_price():
    from app.services.pricing_service import PricingEngine

    records = [reference_fixture(unit="bunch"), reference_fixture(unit="quintal")]
    engine = PricingEngine(MagicMock())
    engine.pricing_repo.get_active_commission = AsyncMock(return_value=None)
    with patch(
        "app.services.pricing_service.MarketDiscoveryService.lookup",
        AsyncMock(
            return_value={
                "records": records,
                "live": False,
                "source": "Synthetic",
                "message": "Synthetic only",
            }
        ),
    ):
        r = await engine.calculate_pricing(
            "Paddy",
            "Grains",
            2,
            "KG",
            "A",
            "Unknown",
            "civai",
            "test-farmer",
            selling_price_per_unit_paise=4321,
        )
    assert (
        r["farmer_payout_per_unit_paise"] == 4321
        and r["reference_price_unit"] == "quintal"
    )
    assert (
        r["reference_price_per_listing_unit_paise"] == 3000
        and r["reference_observation_count"] == 3
    )
