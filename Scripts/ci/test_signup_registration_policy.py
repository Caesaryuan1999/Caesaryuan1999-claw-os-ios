#!/usr/bin/env python3
"""Guard the CLAW OS signup request against server-restricted fields."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SIGNUP = ROOT / "Tinodios" / "SignupViewController.swift"


def main() -> None:
    source = SIGNUP.read_text(encoding="utf-8")

    assert "ClawAuthInput.inviteCredentialMethod" in source, (
        "Signup must submit the invite code as an invite credential."
    )
    assert "createAccountBasic" in source, "Signup account request is missing."
    assert "tags: nil" in source, (
        "Signup must not submit basic:/alias: tags. The server owns restricted "
        "account-name tags and rejects client assignment with HTTP 403."
    )
    assert "let tags = [AccountNames.exactLookupQuery" not in source, (
        "Signup still constructs server-restricted account-name tags."
    )


if __name__ == "__main__":
    main()
