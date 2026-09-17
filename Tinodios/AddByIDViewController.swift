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
    private let lookup = ClawPublicDirectoryLookup()

    @IBOutlet weak var showCodeButton: UIButton!
    @IBOutlet weak var scanCodeButton: UIButton!

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var idTextField: UITextField!
    @IBOutlet weak var okayButton: UIButton!
    @IBOutlet weak var qrcodeImageView: UIImageView!
    @IBOutlet weak var cameraPreviewView: UIView!

    private weak var contentStackView: UIStackView?
    private var qrContainerWidthConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("查找联系人", comment: "Find contacts title")
        view.backgroundColor = ClawTheme.background
        titleLabel.textColor = ClawTheme.ink
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        ClawTheme.styleTextField(idTextField)
        ClawTheme.stylePrimaryButton(okayButton)
        ClawTheme.styleRoundedIconButton(showCodeButton, symbolName: "qrcode", selected: true)
        ClawTheme.styleRoundedIconButton(scanCodeButton, symbolName: "viewfinder")
        showCodeButton.setTitle(NSLocalizedString("显示二维码", comment: "Show QR code"), for: .normal)
        scanCodeButton.setTitle(NSLocalizedString("扫描二维码", comment: "Scan QR code"), for: .normal)
        showCodeButton.accessibilityLabel = NSLocalizedString("显示二维码", comment: "Show QR code")
        scanCodeButton.accessibilityLabel = NSLocalizedString("扫描二维码", comment: "Scan QR code")
        ClawTheme.styleCard(qrcodeImageView)
        cameraPreviewView.layer.cornerRadius = ClawTheme.cardRadius
        cameraPreviewView.layer.cornerCurve = .continuous
        cameraPreviewView.clipsToBounds = true

        self.idTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.tinode = Cache.tinode
        UiUtils.dismissKeyboardForTaps(onView: self.view)

        idTextField.placeholder = NSLocalizedString("完整 CLAW号", comment: "Placeholder for contact lookup")
        okayButton.setTitle(NSLocalizedString("确认", comment: "Confirm contact lookup"), for: .normal)
        idTextField.autocorrectionType = .no
        idTextField.autocapitalizationType = .none
        qrcodeImageView.image = Utils.generateQRCode(from: "https://veilping.app/")
        configureLayout()
    }

    private func configureLayout() {
        guard let qrContainer = qrcodeImageView.superview,
              let contentStack = qrContainer.superview as? UIStackView else {
            return
        }

        contentStackView = contentStack
        contentStack.alignment = .center
        contentStack.spacing = 12

        // Use wider horizontal margins for the lookup row while keeping the QR card compact.
        for constraint in view.constraints {
            guard constraint.firstAttribute == .leading || constraint.firstAttribute == .trailing else { continue }
            if (constraint.firstItem as AnyObject?) === contentStack ||
                (constraint.secondItem as AnyObject?) === contentStack {
                constraint.constant = 24
            }
        }

        if let searchRow = contentStack.arrangedSubviews
            .compactMap({ $0 as? UIStackView })
            .first(where: { $0.arrangedSubviews.contains { $0 === idTextField } }) {
            searchRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            searchRow.heightAnchor.constraint(equalToConstant: 48).isActive = true
            idTextField.heightAnchor.constraint(equalToConstant: 48).isActive = true
            okayButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
            okayButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }

        if let actionRow = contentStack.arrangedSubviews
            .compactMap({ $0 as? UIStackView })
            .first(where: { $0.arrangedSubviews.contains { $0 === showCodeButton } }) {
            actionRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            actionRow.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        titleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        let qrWidth = qrContainer.widthAnchor.constraint(equalToConstant: 240)
        qrWidth.isActive = true
        qrContainerWidthConstraint = qrWidth
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let contentStack = contentStackView,
              let qrWidth = qrContainerWidthConstraint else { return }
        let compactSide = min(252, max(188, contentStack.bounds.width - 32))
        if abs(qrWidth.constant - compactSide) > 0.5 {
            qrWidth.constant = compactSide
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        self.setInterfaceColors()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        lookup.invalidate()
        qrScanner?.stop()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        self.view.backgroundColor = ClawTheme.background
        titleLabel.textColor = ClawTheme.ink
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
        lookup.invalidate()
        okayButton.isEnabled = true
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


        ClawTheme.styleRoundedIconButton(showCodeButton, symbolName: "qrcode", selected: true)
        ClawTheme.styleRoundedIconButton(scanCodeButton, symbolName: "viewfinder")
    }

    @IBAction func scanCodePressed(_ sender: Any) {
        cameraPreviewView.isHidden = false
        qrcodeImageView.isHidden = true

        scanQRCode()

        titleLabel.text = NSLocalizedString("扫描二维码", comment: "Title for camera preview when scanning a QR code")

        ClawTheme.styleRoundedIconButton(showCodeButton, symbolName: "qrcode")
        ClawTheme.styleRoundedIconButton(scanCodeButton, symbolName: "viewfinder", selected: true)
    }

    func handleCodeEntered(_ value: String) {
        guard let owner = tinode, Cache.isCurrent(owner), owner.isConnectionAuthenticated else {
            UiUtils.showToast(message: "服务暂不可用")
            okayButton.isEnabled = true
            return
        }
        guard let ticket = lookup.begin(input: value, owner: owner) else {
            UiUtils.showToast(message: "请输入完整 CLAW号，不支持查询表达式")
            okayButton.isEnabled = true
            return
        }
        let fnd = owner.getOrCreateFndTopic()
        let attached = fnd.attached ? PromisedReply<ServerMessage>(value: ServerMessage()) : fnd.subscribe(set: nil, get: nil)
        attached.thenApply { [weak self] _ in
            guard let self = self, Cache.isCurrent(owner),
                  self.lookup.isCurrent(ticket, owner: owner, input: ticket.input) else {
                return PromisedReply<ServerMessage>(error: NSError(domain: "CLAWOS.Find", code: 4))
            }
            return fnd.setMeta(desc: MetaSetDesc(pub: ticket.wireQuery, priv: nil))
        }.thenApply { [weak self] _ in
            guard let self = self, Cache.isCurrent(owner),
                  self.lookup.isCurrent(ticket, owner: owner, input: ticket.input) else {
                return PromisedReply<ServerMessage>(error: NSError(domain: "CLAWOS.Find", code: 4))
            }
            return fnd.getMeta(query: MsgGetMeta.sub())
        }.then(onSuccess: { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, Cache.isCurrent(owner),
                      self.lookup.isCurrent(ticket, owner: owner, input: self.idTextField.text) else { return }
                self.okayButton.isEnabled = true
                // Only this request's response is evidence. Never fall back to fnd's shared cache.
                let subs = response?.meta?.sub?.compactMap { $0 as? FndSubscription } ?? []
                for sub in subs {
                    if self.lookup.consume(ticket, owner: owner, input: self.idTextField.text, subscription: sub, action: { returnedUID in
                        guard Cache.ifCurrent(owner, {
                            ContactsManager.default.processSubscription(sub: sub)
                            return true
                        }) == true else { return }
                        self.presentChatReplacingCurrentVC(with: returnedUID)
                    }) { return }
                }
                UiUtils.showToast(message: "未找到该 CLAW号")
            }
            return nil
        }, onFailure: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, Cache.isCurrent(owner),
                      self.lookup.isCurrent(ticket, owner: owner, input: self.idTextField.text) else { return }
                self.okayButton.isEnabled = true
                UiUtils.showToast(message: "查找失败，请检查连接后重试")
            }
            return nil
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
        UiUtils.showToast(message: NSLocalizedString("暂不支持私密 ID 二维码，请输入完整 CLAW号", comment: "Private ID search is disabled"))
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            self?.qrScanner?.start()
        }
    }
}
