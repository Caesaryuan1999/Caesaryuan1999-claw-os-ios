//
//  AddByIDViewController.swift
//  Tinodios
//
//  Copyright © 2019-2023 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class AddByIDViewController: UIViewController {
    private var qrScanner: QRScanner?
    private var tinode: Tinode!

    @IBOutlet weak var showCodeButton: UIButton!
    @IBOutlet weak var scanCodeButton: UIButton!

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var idTextField: UITextField!
    @IBOutlet weak var okayButton: UIButton!
    @IBOutlet weak var qrcodeImageView: UIImageView!
    @IBOutlet weak var cameraPreviewView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.idTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.tinode = Cache.tinode
        UiUtils.dismissKeyboardForTaps(onView: self.view)

        showCodeButton.tintColor = UIColor.label.inverted
        idTextField.placeholder = NSLocalizedString("用户名或账号名", comment: "Placeholder for contact lookup")
        idTextField.autocorrectionType = .no
        idTextField.autocapitalizationType = .none
        qrcodeImageView.image = Utils.generateQRCode(from: "https://veilping.app/")
    }

    override func viewDidAppear(_ animated: Bool) {
        self.setInterfaceColors()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        qrScanner?.stop()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        if traitCollection.userInterfaceStyle == .dark {
            self.view.backgroundColor = .black
        } else {
            self.view.backgroundColor = .white
        }
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func okayClicked(_ sender: Any) {
        let query = UiUtils.ensureDataInTextField(idTextField)
        guard !query.isEmpty else { return }
        okayButton.isEnabled = false
        handleCodeEntered(query)
    }

    @IBAction func showCodePressed(_ sender: Any) {
        if let cs = self.qrScanner {
            cs.stop()
            self.qrScanner = nil
        }

        cameraPreviewView.isHidden = true
        qrcodeImageView.isHidden = false

        titleLabel.text = NSLocalizedString("CLAW OS", comment: "Title for displaying app QR Code")


        showCodeButton.tintColor = UIColor.label.inverted
        showCodeButton.backgroundColor = UIColor.link
        scanCodeButton.tintColor = UIColor.link
        scanCodeButton.backgroundColor = UIColor.systemBackground
    }

    @IBAction func scanCodePressed(_ sender: Any) {
        cameraPreviewView.isHidden = false
        qrcodeImageView.isHidden = true

        scanQRCode()

        titleLabel.text = NSLocalizedString("Scan Code", comment: "Title for camera preview when scanning a QR code")

        showCodeButton.tintColor = UIColor.link
        showCodeButton.backgroundColor = UIColor.systemBackground
        scanCodeButton.tintColor = UIColor.label.inverted
        scanCodeButton.backgroundColor = UIColor.link
    }

    private func normalizeLookupInput(_ value: String) -> String {
        var query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.first == "@" {
            query = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return query
    }

    private func isPrivateUserId(_ value: String?) -> Bool {
        guard let value = value else { return false }
        return AccountNames.isUserIdLike(value) || Tinode.topicTypeByName(name: value) == .p2p
    }

    private func findMatchingUserId(in subs: [FndSubscription]?, query: String) -> String? {
        guard let subs = subs else { return nil }
        for sub in subs {
            let candidate = sub.user ?? sub.topic
            guard Tinode.topicTypeByName(name: candidate) == .p2p,
                  AccountNames.matchesPublicSearchName(tags: sub.priv, query: query) else {
                continue
            }
            return candidate
        }
        return nil
    }

    private func findMatchingUserId(response: ServerMessage?, fnd: DefaultFndTopic, query: String) -> String? {
        if let subs = response?.meta?.sub?.compactMap({ $0 as? FndSubscription }),
           let match = findMatchingUserId(in: subs, query: query) {
            return match
        }
        return findMatchingUserId(in: fnd.getSubscriptions(), query: query)
    }

    func handleCodeEntered(_ value: String) {
        let query = normalizeLookupInput(value)
        guard !query.isEmpty else {
            okayButton.isEnabled = true
            return
        }
        guard !isPrivateUserId(query) else {
            UiUtils.showToast(message: NSLocalizedString("不能通过 ID 搜索，请输入用户名或账号名", comment: "Private ID search is disabled"))
            okayButton.isEnabled = true
            return
        }
        guard let searchQuery = AccountNames.directorySearchQuery(query) else {
            UiUtils.showToast(message: NSLocalizedString("请输入有效的用户名或账号名", comment: "Invalid contact lookup query"))
            okayButton.isEnabled = true
            return
        }
        guard tinode.isConnectionAuthenticated else {
            UiUtils.showToast(message: NSLocalizedString("服务暂不可用", comment: "Unable to use service"))
            okayButton.isEnabled = true
            return
        }
        UiUtils.attachToFndTopic(fndListener: nil)?.then(
            onSuccess: { [weak self] msg in
                guard let self = self else { return nil }
                let fnd = self.tinode.getOrCreateFndTopic()
                return fnd.setMeta(desc: MetaSetDesc(pub: searchQuery, priv: nil)).thenApply { _ in
                    return fnd.getMeta(query: MsgGetMeta.sub())
                }.then(
                    onSuccess: { [weak self] response in
                        guard let self = self else { return nil }
                        guard let userId = self.findMatchingUserId(response: response, fnd: fnd, query: query) else {
                            DispatchQueue.main.async {
                                UiUtils.showToast(message: NSLocalizedString("未找到该用户", comment: "Contact lookup no match"))
                            }
                            return nil
                        }
                        if let sub = response?.meta?.sub?.compactMap({ $0 as? FndSubscription }).first(where: { $0.uniqueId == userId }) ??
                            fnd.getSubscriptions()?.first(where: { $0.uniqueId == userId }) {
                            ContactsManager.default.processSubscription(sub: sub)
                        }
                        self.presentChatReplacingCurrentVC(with: userId)
                        return nil
                    },
                    onFailure: { err in
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: String(format: NSLocalizedString("查找失败：%@", comment: "Contact lookup failure"), err.localizedDescription))
                        }
                        return nil
                    })
            },
            onFailure: { err in
                DispatchQueue.main.async {
                    UiUtils.showToast(message: String(format: NSLocalizedString("查找失败：%@", comment: "Contact lookup failure"), err.localizedDescription))
                }
                return nil
            }).thenFinally({ [weak self] in
                DispatchQueue.main.async {
                    if self?.okayButton.isEnabled == false {
                        self?.okayButton.isEnabled = true
                    }
                }
            })
    }

    func scanQRCode() {
        if qrScanner == nil {
            qrScanner = QRScanner(embedIn: self.cameraPreviewView, expectedCodePrefix: Utils.kTopicUriPrefix, delegate: self)
            qrScanner?.start()
        }
    }
}

extension AddByIDViewController: QRScannerDelegate {
    func qrScanner(didScanCode codeValue: String?) {
        guard codeValue != nil else {
            Cache.log.error("Invalid CLAW OS QR code")
            DispatchQueue.main.async {
                UiUtils.showToast(message: NSLocalizedString("无效的 CLAW OS 二维码", comment: "Invalid QR code"))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                // Restart QR scanner.
                self?.qrScanner?.start()
            }
            return
        }
        UiUtils.showToast(message: NSLocalizedString("不能通过 ID 搜索，请输入用户名或账号名", comment: "Private ID search is disabled"))
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            self?.qrScanner?.start()
        }
    }
}
