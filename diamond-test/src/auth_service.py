"""Issue 1: basic auth service.

Provides a minimal authentication service with login/logout.
Issue 3 wires this to the user model.
"""
from __future__ import annotations

from typing import Optional

from .user_model import User


class AuthService:
    """A minimal in-memory auth service."""

    def __init__(self) -> None:
        self._sessions: dict[str, User] = {}

    def login(self, user: User, password: str) -> Optional[str]:
        if user.verify_password(password):
            token = f"token-{user.username}"
            self._sessions[token] = user
            return token
        return None

    def logout(self, token: str) -> bool:
        return self._sessions.pop(token, None) is not None

    def current_user(self, token: str) -> Optional[User]:
        return self._sessions.get(token)
