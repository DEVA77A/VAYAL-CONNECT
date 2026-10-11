"""
VayalConnect Backend — Order Service

Handles order creation with atomic inventory reservation,
financial snapshot embedding, and state machine transitions.
"""

from typing import Optional, Dict, Any, List
from datetime import datetime, timezone
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.repositories.orders import OrderRepository
from app.repositories.products import ProductRepository
from app.repositories.users import UserRepository
from app.repositories.pricing import PricingRepository
from app.services.audit_service import AuditService
from app.core.exceptions import (
    NotFoundError, ProductOutOfStockError, ValidationError,
    ForbiddenError, DuplicateOrderError, InvalidStateTransitionError,
    FarmerNotApprovedError,
)
from app.schemas.common import (
    OrderStatus, PaymentStatus, PayoutStatus, VALID_ORDER_TRANSITIONS,
)
from app.utils.money import safe_multiply, format_rupees

logger = logging.getLogger(__name__)


class OrderService:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.order_repo = OrderRepository(db)
        self.product_repo = ProductRepository(db)
        self.user_repo = UserRepository(db)
        self.pricing_repo = PricingRepository(db)
        self.audit_service = AuditService(db)

    async def create_order(
        self,
        buyer_id: str,
        product_id: str,
        quantity: int,
        idempotency_key: Optional[str] = None,
        fulfillment_method: str = "PICKUP",
        delivery_address: Optional[dict] = None,
        expected_unit_price_paise: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        Create an order with atomic inventory reservation.

        CRITICAL: Price comes from stored product/snapshot data.
        NEVER from the mobile app.
        """
        from app.schemas.order import CreateOrderRequest
        validated = CreateOrderRequest(product_id=product_id, quantity=quantity, idempotency_key=idempotency_key,
                                       fulfillment_method=fulfillment_method, delivery_address=delivery_address, expected_unit_price_paise=expected_unit_price_paise)
        delivery_address = validated.delivery_address.model_dump() if validated.delivery_address else None
        # Idempotency check
        if idempotency_key:
            existing = await self.order_repo.find_by_idempotency_key(idempotency_key)
            if existing:
                from app.core.exceptions import ForbiddenError
                if existing.get("buyer_id") != buyer_id:
                    raise ForbiddenError("Order does not belong to you.")
                if existing.get("product_id") != product_id or existing.get("quantity") != quantity:
                    raise ValidationError("Idempotency key was already used for a different order.")
                if existing.get("fulfillment_method", "PICKUP") != fulfillment_method or existing.get("delivery_address") != delivery_address:
                    raise ValidationError("Idempotency key was already used for different fulfillment details.")
                return existing

        # Validate product
        product = await self.product_repo.find_active_by_id(product_id)
        if not product:
            raise NotFoundError("Product")

        # Validate farmer is approved
        farmer_id = product["farmer_id"]
        from app.repositories.farmers import FarmerRepository
        farmer_repo = FarmerRepository(self.db)
        farmer_profile = await farmer_repo.find_by_user_id(farmer_id)
        if not farmer_profile or farmer_profile.get("approval_status") != "APPROVED":
            raise FarmerNotApprovedError()

        application = farmer_profile.get("application") or {}
        if fulfillment_method == "DELIVERY" and not application.get("delivery_available", False):
            raise ValidationError("This farmer does not offer delivery.")
        pickup_address = application.get("pickup_address") or product.get("location", "")
        # Validate buyer is not the farmer
        if buyer_id == farmer_id:
            raise ValidationError("You cannot purchase your own product.")

        # Validate quantity
        if quantity <= 0:
            raise ValidationError("Quantity must be greater than zero.")
        if quantity > product.get("quantity_available", 0):
            raise ProductOutOfStockError()

        # Atomic inventory reservation
        reserved = await self.product_repo.atomic_reserve_quantity(product_id, quantity)
        if not reserved:
            raise ProductOutOfStockError()

        order_persisted = False
        try:
            # Use the reserved document so a simultaneous listing edit cannot change this checkout.
            if isinstance(reserved, dict):
                product = reserved
            from app.services.pricing_service import PricingEngine
            product = await PricingEngine(self.db).buyer_pricing(product)
            if expected_unit_price_paise is not None and product["buyer_price_per_unit_paise"] != expected_unit_price_paise:
                from app.core.exceptions import ConflictError
                raise ConflictError("PRICE_CHANGED", "Price changed. Reload the listing before placing your order.")
            # Get server pricing; commission and fulfillment are frozen in this order.
            buyer_unit_price = product["buyer_price_per_unit_paise"]
            farmer_unit_payout = product["farmer_payout_per_unit_paise"]
            commission_per_unit = product["commission_per_unit_paise"]
            commission_bps = product["commission_percentage"]

            # Calculate totals — NEVER trust client values
            buyer_total = safe_multiply(buyer_unit_price, quantity)
            farmer_total = safe_multiply(farmer_unit_payout, quantity)
            commission_total = safe_multiply(commission_per_unit, quantity)

            # Generate order number
            order_number = await self.order_repo.generate_order_number()

            # Get product name and farmer info
            farmer = await self.user_repo.find_by_id(farmer_id)
            farmer_name = farmer["name"] if farmer else "Unknown"
            buyer = await self.user_repo.find_by_id(buyer_id)
            buyer_name = buyer["name"] if buyer else "Unknown"

            # Create order document with complete financial snapshot
            order_doc = {
                "order_number": order_number,
                "fulfillment_method": fulfillment_method,
                "delivery_address": delivery_address,
                "pickup_address": pickup_address if fulfillment_method == "PICKUP" else None,
                "delivery_fee_paise": 0,
                "commission_config_id": product.get("commission_config_id"),
                "commission_config_version": product.get("commission_config_version"),
                "pricing_mode": product.get("pricing_mode"),
                "buyer_id": buyer_id,
                "farmer_id": farmer_id,
                "product_id": product_id,
                "product_name": product.get("product_name", ""),
                "farmer_name": farmer_name,
                "buyer_name": buyer_name,
                "pricing_snapshot_id": product.get("pricing_snapshot_id"),
                "quantity": quantity,
                "quantity_unit": product.get("quantity_unit", "KG"),
                # Frozen financial data — IMMUTABLE after creation
                "buyer_unit_price_paise": buyer_unit_price,
                "buyer_total_paise": buyer_total,
                "farmer_unit_payout_paise": farmer_unit_payout,
                "farmer_total_payout_paise": farmer_total,
                "commission_percentage_bps": commission_bps,
                "commission_unit_amount_paise": commission_per_unit,
                "commission_total_paise": commission_total,
                "government_reference_price_paise": product.get(
                    "government_reference_price_paise", 0
                ),
                "reference_price_date": product.get("reference_price_date"),
                # Status fields
                "order_status": OrderStatus.PENDING_PAYMENT.value,
                "payment_status": PaymentStatus.PENDING.value,
                "payout_status": PayoutStatus.NOT_INITIATED.value,
                "idempotency_key": idempotency_key,
            }

            order_id = await self.order_repo.create(order_doc)
            order_persisted = True

            await self.audit_service.log(
                actor_id=buyer_id,
                actor_role="BUYER",
                action="ORDER_CREATED",
                entity_type="order",
                entity_id=order_id,
                details={
                    "product_id": product_id,
                    "quantity": quantity,
                    "buyer_total_paise": buyer_total,
                },
            )

            # Return order with ID
            order_doc["id"] = order_id
            return order_doc

        except Exception as e:
            # Restore quantity on failure
            if not order_persisted:
                await self.product_repo.restore_quantity(product_id, quantity)
            logger.error("Order creation failed (%s); persisted=%s", type(e).__name__, order_persisted)
            raise

    async def get_order(self, order_id: str) -> Optional[Dict[str, Any]]:
        return await self.order_repo.find_by_id(order_id)

    async def list_buyer_orders(
        self, buyer_id: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        return await self.order_repo.list_by_buyer(buyer_id, page, limit)

    async def list_farmer_orders(
        self, farmer_id: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        return await self.order_repo.list_by_farmer(farmer_id, page, limit)

    async def list_all_orders(
        self, status: Optional[str] = None, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        return await self.order_repo.list_all(status, page, limit)

    async def update_order_status(
        self, order_id: str, new_status: str, actor_id: str, actor_role: str
    ) -> bool:
        """Update order status with state machine validation."""
        order = await self.order_repo.find_by_id(order_id)
        if not order:
            raise NotFoundError("Order")

        current_status = order["order_status"]
        valid_transitions = VALID_ORDER_TRANSITIONS.get(
            OrderStatus(current_status), []
        )

        try:
            new_status_enum = OrderStatus(new_status)
        except ValueError:
            raise ValidationError(f"Invalid order status: {new_status}")

        if new_status_enum not in valid_transitions:
            raise InvalidStateTransitionError(current_status, new_status)

        success = await self.order_repo.update_status(order_id, new_status)

        if success:
            await self.audit_service.log(
                actor_id=actor_id,
                actor_role=actor_role,
                action="ORDER_STATUS_UPDATED",
                entity_type="order",
                entity_id=order_id,
                details={"from": current_status, "to": new_status},
            )

        return success

    async def cancel_order(
        self, order_id: str, actor_id: str, actor_role: str, reason: Optional[str] = None
    ):
        """Cancel an order and restore inventory."""
        order = await self.order_repo.find_by_id(order_id)
        if not order:
            raise NotFoundError("Order")

        # Only PENDING_PAYMENT or CONFIRMED orders can be cancelled
        if order["order_status"] not in (
            OrderStatus.PENDING_PAYMENT.value,
            OrderStatus.CONFIRMED.value,
        ):
            raise InvalidStateTransitionError(
                order["order_status"], OrderStatus.CANCELLED.value
            )

        # Ownership check for buyer
        if actor_role == "BUYER" and order["buyer_id"] != actor_id:
            raise ForbiddenError("You can only cancel your own orders.")

        if actor_role not in ("BUYER", "ADMIN"):
            raise ForbiddenError("Only the owning buyer or an administrator may cancel an order.")

        # Restore quantity
        await self.product_repo.restore_quantity(
            order["product_id"], order["quantity"]
        )

        # Update status
        await self.order_repo.update_status(
            order_id,
            OrderStatus.CANCELLED.value,
            cancellation_reason=reason,
            cancelled_at=datetime.now(timezone.utc),
            cancelled_by=actor_id,
        )

        await self.audit_service.log(
            actor_id=actor_id,
            actor_role=actor_role,
            action="ORDER_CANCELLED",
            entity_type="order",
            entity_id=order_id,
            details={"reason": reason},
        )
