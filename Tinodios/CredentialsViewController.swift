//
//  CredentialsViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class CredentialsViewController: UIViewController {
    private var sessionOwner: Tinode?
    var identityCoordinator: ClawIdentityCoordinator?
    var identityLegalAccepted = false
    private var identityForm: ClawIdentityForm?
    private var verifyButton: UIButton?
    private var resendButton: UIButton?
    private var identityTimer: Timer?

    @IBOutlet weak var codeText: UITextField!

    var meth: String?
    var authToken: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        if identityCoordinator != nil { installIdentityVerification(); return }
        sessionOwner = Cache.tinode
        title = NSLocalizedString("验证账号", comment: "Verify account title")
        self.view.backgroundColor = ClawTheme.background
        ClawTheme.styleTextField(codeText)
        self.authToken = sessionOwner?.authToken
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        identityTimer?.invalidate()
        if identityCoordinator != nil {
            if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
                codeText.text = nil
                identityCoordinator?.flow.invalidate()
            }
            return
        }
        if self.isMovingFromParent {
            // If the user's logged in and is voluntarily leaving the verification VC
            // by hitting the Back button.
            guard let tinode = sessionOwner, Cache.isCurrent(tinode) else { return }
            if tinode.isConnectionAuthenticated || tinode.myUid != nil {
                Cache.invalidate(ifCurrent: tinode)
            }
        }
    }

    @IBAction func onConfirm(_ sender: UIButton) {
        if identityCoordinator != nil { verifyIdentityCode(); return }
        guard let code = codeText.text else {
            return
        }
        guard let method = meth else {
            return
        }

        guard let tinode = sessionOwner, Cache.isCurrent(tinode) else { return }

        guard let token = self.authToken else {
            self.dismiss(animated: true, completion: nil)
            return
        }

        let c = Credential(meth: method, val: nil, resp: code, params: nil)
        var creds = [Credential]()
        creds.append(c)

        let errorMsgTemplate = NSLocalizedString("Verification failure: %d %@", comment: "Error message")
        tinode.loginToken(token: token, creds: creds)
            .then(onSuccess: { msg in
                guard Cache.isCurrent(tinode) else { return nil }
                if let ctrl = msg?.ctrl, ctrl.code >= 300 {
                    DispatchQueue.main.async {
                        guard Cache.isCurrent(tinode) else { return }
                        UiUtils.showToast(message: String(format: errorMsgTemplate, ctrl.code, ctrl.text))
                    }
                } else {
                    if let token = tinode.authToken {
                        tinode.setAutoLoginWithToken(token: token)
                    }
                    UiUtils.routeToChatListVC(for: tinode)
                }
                return nil
            }, onFailure: { err in
                Cache.log.error("Error validating credentials: %@", err.localizedDescription)
                DispatchQueue.main.async {
                    guard Cache.isCurrent(tinode) else { return }
                    UiUtils.showToast(message: String(format: errorMsgTemplate, -1, "Invalid code"))
                }
                return nil
            })
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if identityCoordinator != nil {
            identityTimer?.invalidate()
            identityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.refreshIdentityControls()
            }
        }
    }
    deinit { identityTimer?.invalidate() }

    private func installIdentityVerification() {
        title = "输入验证码"
        view.backgroundColor = ClawTheme.background
        let form = ClawIdentityForm(title: "输入验证码", detail: "验证码请求已提交，请查看短信或邮件。提交不代表已送达。")
        identityForm = form
        let code = form.field("6 位数字验证码")
        code.keyboardType = .numberPad
        code.textContentType = .oneTimeCode
        code.accessibilityIdentifier = "claw.identity.code"
        codeText = code
        verifyButton = form.button("验证", target: self, action: #selector(verifyIdentityCode))
        resendButton = form.button("重新获取验证码", target: self, action: #selector(resendIdentityCode), primary: false)
        _ = form.button("重新选择手机号或邮箱", target: self, action: #selector(returnToIdentityEntry), primary: false)
        form.finish()
        form.install(in: self)
        UiUtils.dismissKeyboardForTaps(onView: view)
        refreshIdentityControls()
    }

    private func refreshIdentityControls() {
        guard let flow = identityCoordinator?.flow else { return }
        verifyButton?.isEnabled = flow.isCurrent && !flow.busy && flow.canVerify
        verifyButton?.setTitle(flow.busy ? "正在处理…" : "验证", for: .normal)
        codeText.isEnabled = !flow.busy
        resendButton?.isEnabled = flow.isCurrent && !flow.busy && (flow.pendingChallenge != nil || flow.retrySeconds == 0)
        resendButton?.setTitle(flow.pendingChallenge != nil ? "重试确认请求" :
            flow.retrySeconds > 0 ? "\(flow.retrySeconds) 秒后重新获取" : "重新获取验证码", for: .normal)
    }
    @objc private func verifyIdentityCode() {
        guard let coordinator = identityCoordinator else { return }
        coordinator.flow.verify(code: codeText.text ?? "") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.codeText.text = nil
                self.navigationController?.pushViewController(ClawSetIdentityPasswordViewController(coordinator: coordinator), animated: true)
            case let .failure(error):
                self.identityForm?.status.text = error.message
                if !coordinator.flow.canVerify {
                    self.identityForm?.status.text = "\(error.message)。请重新获取验证码后继续。"
                    self.codeText.text = nil
                }
            }
            self.refreshIdentityControls()
        }
        refreshIdentityControls()
    }
    @objc private func resendIdentityCode() {
        guard let coordinator = identityCoordinator, let method = coordinator.flow.method,
              let value = coordinator.flow.value else { returnToIdentityEntry(); return }
        coordinator.flow.requestCode(method: method, input: value,
            legalResourcesAvailable: identityLegalAccepted, termsAccepted: identityLegalAccepted) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.codeText.text = nil
                    self.identityForm?.status.text = "请求已提交，请等待短信或邮件。"
                case let .failure(error): self.identityForm?.status.text = error.message
                }
                self.refreshIdentityControls()
            }
        refreshIdentityControls()
    }
    @objc private func returnToIdentityEntry() {
        codeText.text = nil
        identityCoordinator?.flow.invalidate()
        navigationController?.popViewController(animated: true)
    }

}
