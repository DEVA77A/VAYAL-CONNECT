"""
VayalConnect Backend — Exception Hierarchy

Consistent error codes and HTTP responses.
No stack traces or internal details leaked to clients.
"""

from typing import Optional, Any


class VayalConnectError(Exception):
    """Base exception for all VayalConnect errors."""

    def __init__(
        self,
        code: str,
        message: str,
        status_code: int = 500,
        details: Optional[Any] = None,
    ):
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details
        super().__init__(message)

    @property
    def error_code(self) -> str:
        """Alias for code — used by exception handler."""
        return self.code

    @property
    def detail(self) -> str:
        """Alias for message — used by exception handler."""
        return self.message


# ============================================================
# Authentication Errors
# ============================================================

class UnauthorizedError(VayalConnectError):
    def __init__(self, message: str = "Authentication required."):
        super().__init__("UNAUTHORIZED", message, 401)


class InvalidCredentialsError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "INVALID_CREDENTIALS",
            "Invalid email or password.",
            401,
        )


class TokenExpiredError(VayalConnectError):
    def __init__(self):
        super().__init__("TOKEN_EXPIRED", "Token has expired.", 401)


class InvalidTokenError(VayalConnectError):
    def __init__(self):
        super().__init__("INVALID_TOKEN", "Invalid or malformed token.", 401)


# ============================================================
# Authorization Errors
# ============================================================

class ForbiddenError(VayalConnectError):
    def __init__(self, message: str = "You do not have permission to access this resource."):
        super().__init__("FORBIDDEN", message, 403)


class InsufficientRoleError(VayalConnectError):
    def __init__(self, required_role: str):
        super().__init__(
            "INSUFFICIENT_ROLE",
            f"This action requires {required_role} role.",
            403,
        )


# ============================================================
# Resource Errors
# ============================================================

class NotFoundError(VayalConnectError):
    def __init__(self, resource: str = "Resource"):
        super().__init__(
            "NOT_FOUND",
            f"{resource} not found.",
            404,
        )


class ConflictError(VayalConnectError):
    def __init__(self, code: str, message: str):
        super().__init__(code, message, 409)


class EmailAlreadyExistsError(ConflictError):
    def __init__(self):
        super().__init__("EMAIL_ALREADY_EXISTS", "An account with this email already exists.")


class PhoneAlreadyExistsError(ConflictError):
    def __init__(self):
        super().__init__("PHONE_ALREADY_EXISTS", "An account with this phone number already exists.")


# ============================================================
# Validation Errors
# ============================================================

class ValidationError(VayalConnectError):
    def __init__(self, message: str, details: Optional[Any] = None):
        super().__init__("VALIDATION_ERROR", message, 422, details)


# ============================================================
# OTP Errors
# ============================================================

class OTPExpiredError(VayalConnectError):
    def __init__(self):
        super().__init__("OTP_EXPIRED", "OTP has expired. Please request a new one.", 400)


class OTPInvalidError(VayalConnectError):
    def __init__(self):
        super().__init__("OTP_INVALID", "Invalid OTP code.", 400)


class OTPMaxAttemptsError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "OTP_MAX_ATTEMPTS",
            "Maximum OTP verification attempts exceeded. Please request a new OTP.",
            429,
        )


class OTPCooldownError(VayalConnectError):
    def __init__(self, seconds_remaining: int):
        super().__init__(
            "OTP_COOLDOWN",
            f"Please wait {seconds_remaining} seconds before requesting a new OTP.",
            429,
        )


# ============================================================
# Business Logic Errors
# ============================================================

class ProductOutOfStockError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "PRODUCT_OUT_OF_STOCK",
            "The requested quantity is not available.",
            409,
        )


class MarketPriceUnavailableError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "MARKET_PRICE_UNAVAILABLE",
            "Current market price is temporarily unavailable.",
            503,
        )


class FarmerNotApprovedError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "FARMER_NOT_APPROVED",
            "Farmer account is pending approval.",
            403,
        )


class PayoutNotEligibleError(VayalConnectError):
    def __init__(self, message: str = "Payout cannot be processed at this time."):
        super().__init__("PAYOUT_NOT_ELIGIBLE", message, 400)


# ============================================================
# Payment Errors
# ============================================================

class PaymentVerificationFailedError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "PAYMENT_VERIFICATION_FAILED",
            "Payment verification failed. Invalid signature.",
            400,
        )


class PaymentAlreadyVerifiedError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "PAYMENT_ALREADY_VERIFIED",
            "This payment has already been verified.",
            409,
        )


class DuplicateOrderError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "DUPLICATE_ORDER",
            "An order with this idempotency key already exists.",
            409,
        )


# ============================================================
# Rate Limiting
# ============================================================

class EmailDeliveryError(VayalConnectError):
    def __init__(self):
        super().__init__("EMAIL_DELIVERY_FAILED", "Unable to send OTP email. Please try again later.", 503)


class RateLimitExceededError(VayalConnectError):
    def __init__(self):
        super().__init__(
            "RATE_LIMIT_EXCEEDED",
            "Too many requests. Please try again later.",
            429,
        )


# ============================================================
# Financial Errors
# ============================================================

class FinancialInconsistencyError(VayalConnectError):
    def __init__(self, message: str):
        super().__init__(
            "FINANCIAL_INCONSISTENCY",
            message,
            500,
        )


class InvalidStateTransitionError(VayalConnectError):
    def __init__(self, current_state: str, requested_state: str):
        super().__init__(
            "INVALID_STATE_TRANSITION",
            f"Cannot transition from {current_state} to {requested_state}.",
            400,
        )
