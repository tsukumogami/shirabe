"""Issue 4: end-to-end auth flow test (login + logout)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.auth_service import AuthService
from src.user_model import User


def test_e2e_login():
    svc = AuthService()
    user = User(username="alice", password="secret")
    token = svc.login(user, "secret")
    assert token is not None
    assert svc.current_user(token) is user


def test_e2e_login_wrong_password():
    svc = AuthService()
    user = User(username="alice", password="secret")
    assert svc.login(user, "wrong") is None


def test_e2e_logout():
    svc = AuthService()
    user = User(username="bob", password="pw")
    token = svc.login(user, "pw")
    assert svc.logout(token) is True
    assert svc.current_user(token) is None


if __name__ == "__main__":
    test_e2e_login()
    test_e2e_login_wrong_password()
    test_e2e_logout()
    print("ALL E2E TESTS PASSED")
