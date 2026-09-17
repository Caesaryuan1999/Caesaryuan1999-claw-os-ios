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

    @IBOutlet weak var codeText: UITextField!

    var meth: String?
    var authToken: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        sessionOwner = Cache.tinode
        title = NSLocalizedString("验证账号", comment: "Verify account title")
        self.view.backgroundColor = ClawTheme.background
        ClawTheme.styleTextField(codeText)
        self.authToken = sessionOwner?.authToken
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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
}
