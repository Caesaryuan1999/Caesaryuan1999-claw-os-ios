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
    flow = (ROOT / "Tinodios/ClawIdentityFlow.swift").read_text(encoding="utf-8")
    service = (ROOT / "Tinodios/ClawIdentityService.swift").read_text(encoding="utf-8")
    assert "validateLogin" in login and "current.loginLegacy(" in login
    assert "ClawAuthInput.passwordForSubmit" in login
    assert "current.flow.login(" in login
    assert "coordinator?.flow.invalidate()" in login
    assert "ClawIdentityEntryController" in signup and "ClawIdentityEntryController" in reset
    assert "createAccountBasic" not in signup
    assert "private var termsAccepted = false" in utils
    assert "legalResourcesAvailable: legal.available" in utils
    assert "ClawIdentityLegalResources.configured" in utils
    assert "service.register(request)" in flow and "service.reset(request)" in flow
    assert "session.user == http.user" in flow and "self.commitSession(confirmed)" in flow
    assert "self.registeredUser == http.user" in flow
    assert "snapshotIsCurrent()" in flow and "self.generation == generation" in flow
    assert "Cache.ifCurrent(owner)" in utils and "owner.loginToken(token: http.token)" in utils
    assert "注册已完成，暂时无法登录" in utils and "返回登录" in utils
    assert "completionHandler(nil)" in service
    assert 'request.setValue("no-store"' in service
    assert "UserDefaults" not in service and "Log." not in service
    assert "newPasswordIsValid(password)" in flow
    assert "Existing password bytes" in flow
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
    assert "已退出登录" in account and "退出登录失败，请重试" in account
    assert "self!" not in signup

    assert "AuthScheme.idResetInstance" not in reset
    assert "updateAccountBasic(usingAuthScheme" not in reset
    assert "identityPurpose: ClawIdentityPurpose { .reset }" in reset
    assert "legacyRecovery" in service and "管理员恢复账号" in service


if __name__ == "__main__":
    main()
