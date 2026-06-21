"""Issue 2: user model definition."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class User:
    username: str
    password: str

    def verify_password(self, candidate: str) -> bool:
        return self.password == candidate
