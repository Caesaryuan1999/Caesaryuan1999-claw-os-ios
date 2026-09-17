#!/usr/bin/env python3
"""AUTH-A1 replaces invite/basic registration; server owns UID and public identifiers."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def main():
    signup = (ROOT / "Tinodios/SignupViewController.swift").read_text(encoding="utf-8")
    flow = (ROOT / "Tinodios/ClawIdentityFlow.swift").read_text(encoding="utf-8")
    service = (ROOT / "Tinodios/ClawIdentityService.swift").read_text(encoding="utf-8")
    assert "ClawIdentityEntryController" in signup
    for forbidden in ["createAccountBasic", "inviteCredentialMethod", "exactLookupQuery", "UIImagePickerController"]:
        assert forbidden not in signup
    request = service.split("struct ClawIdentityPasswordRequest:")[1].split("struct ClawIdentityLoginRequest:")[0]
    assert "request_id" in request and "proof" in request and "password" in request
    for forbidden in ["username", "invite", "tags", "alias"]:
        assert forbidden not in request
    assert "value.registered, value.login_required, !value.user.isEmpty" in flow
    assert "self.registeredUser = uid" in flow
    assert "self.registeredUser == http.user" in flow
if __name__ == "__main__":
    main()
