"""
Unit tests for Authentication logic:
Password hashing, JWT token creation & decoding, OTP generation and hashing.
"""

import pytest
from datetime import timedelta
from jose import jwt
from app.core.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_otp,
    verify_otp,
)
from app.core.config import settings


def test_password_hashing():
    password = "SuperSecretPassword123!"
    hashed = hash_password(password)

    # Hash should not equal plain text
    assert hashed != password
    # Verification should pass
    assert verify_password(password, hashed) is True
    # Verification with wrong password should fail
    assert verify_password("WrongPassword!", hashed) is False


def test_jwt_access_token():
    payload = {"sub": "user_12345", "role": "FARMER"}
    token = create_access_token(payload)

    # Decode token
    decoded = decode_token(token)
    assert decoded["sub"] == "user_12345"
    assert decoded["role"] == "FARMER"
    assert decoded["type"] == "access"
    assert "exp" in decoded


def test_jwt_refresh_token():
    payload = {"sub": "user_12345", "role": "BUYER"}
    token = create_refresh_token(payload)

    decoded = decode_token(token)
    assert decoded["sub"] == "user_12345"
    assert decoded["role"] == "BUYER"
    assert decoded["type"] == "refresh"


def test_otp_hashing_and_verification():
    otp = "543210"
    hashed = hash_otp(otp)

    assert hashed != otp
    assert verify_otp(otp, hashed) is True
    assert verify_otp("000000", hashed) is False
