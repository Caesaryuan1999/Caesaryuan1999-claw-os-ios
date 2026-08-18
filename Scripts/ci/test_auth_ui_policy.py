#!/usr/bin/env python3
"""Guard CLAW OS iOS authentication UI state and recovery boundaries."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UTILS = ROOT / "Tinodios" / "Utils.swift"
LOGIN = ROOT / "Tinodios" / "LoginViewController.swift"
SIGNUP = ROOT / "Tinodios" / "SignupViewController.swift"
RESET = ROOT / "Tinodios" / "ResetPasswordViewController.swift"
SECURITY = ROOT / "Tinodios" / "SettingsSecurityViewController.swift"
ACCOUNT = ROOT / "Tinodios" / "AccountSettingsViewController.swift"


def main() -> None:
    utils = UTILS.read_text(encoding="utf-8")
    login = LOGIN.read_text(encoding="utf-8")
    signup = SIGNUP.read_text(encoding="utf-8")
    reset = RESET.read_text(encoding="utf-8")
    security = SECURITY.read_text(encoding="utf-8")
    account = ACCOUNT.read_text(encoding="utf-8")

    assert "enum ClawAuthFormValidation" in utils
    assert "enum ClawAuthErrorMessages" in utils
    assert "final class ClawSubmissionGate" in utils
    assert "validateLogin" in login and "submissionGate.begin()" in login
    assert "submissionGate.finish()" in login
    assert "guard let connection = try tinode.connectDefault" in login
    assert "ClawAuthErrorMessages.loginMessage" in login
    assert '"CLAW OS: \\(tinodeErr.description)"' not in login
    assert "validateSignUp" in signup and "submissionGate.begin()" in signup
    assert "submissionGate.finish()" in signup
    assert "guard let connection = try Cache.tinode.connectDefault" in signup
    assert "ClawAuthErrorMessages.signUpMessage" in signup
    assert 'NSLocalizedString("注册失败：%@"' not in signup
    for marker in [
        "installPremiumSignupLayout()",
        "termsAccepted",
        "UIPasteboard.general.string",
        "account.heightAnchor.constraint(equalToConstant: 58)",
        "password.heightAnchor.constraint(equalToConstant: 58)",
        "invite.heightAnchor.constraint(equalToConstant: 58)",
        "submit.heightAnchor.constraint(equalToConstant: 54)",
    ]:
        assert marker in signup, f"missing Figma signup contract: {marker}"
    assert "validatePasswordChange" in security
    assert "submissionGate.begin()" in security
    assert "submissionGate.finish()" in security
    assert "updateAccountBasic(uid: nil, username: nil" in security
    assert "ClawAuthErrorMessages.passwordChangeMessage" in security
    assert "presentPasswordChangeAlert" in security
    assert "再次输入新密码" in security
    assert 'NSLocalizedString("修改密码失败：%@"' not in security
    assert "systemLayoutSizeFitting" in account
    assert "contentInset.bottom" in account
    assert "已成功登出" in account and "登出失败，请重试" in account
    assert "self!" not in signup

    assert "AuthScheme.idResetInstance" not in reset
    assert "updateAccountBasic(usingAuthScheme" not in reset
    assert "暂不开放自助找回密码" in reset


if __name__ == "__main__":
    main()
