//
//  SettingsHelpViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import TinodeSDK
import TinodiosDB
import UIKit

class SettingsHelpViewController: UITableViewController {
    private static let kDefaultRowHeight: CGFloat = 52

    @IBOutlet weak var contactUs: UITableViewCell!
    @IBOutlet weak var termsOfUse: UITableViewCell!
    @IBOutlet weak var privacyPolicy: UITableViewCell!
    @IBOutlet weak var appVersion: UILabel!
    @IBOutlet weak var logoView: UIImageView!
    @IBOutlet weak var serviceNameLabel: UILabel!
    @IBOutlet weak var serviceLinkLabel: UILabel!
    @IBOutlet weak var serverAddressLabel: UILabel!
    @IBOutlet weak var poweredByView: UIView!

    private var isUsingCustomBranding = false
    private var contentHeight: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        title = NSLocalizedString("帮助", comment: "Help settings title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("开源许可", comment: "Open source licenses"),
            style: .plain, target: self, action: #selector(showLicenses))
        view.accessibilityIdentifier = "claw.settings.help.screen"
        view.backgroundColor = ClawTheme.background
        ClawTheme.styleList(tableView, rowHeight: SettingsHelpViewController.kDefaultRowHeight)
        let helpCells: [UITableViewCell] = [contactUs, termsOfUse, privacyPolicy]
        helpCells.forEach { cell in
            ClawTheme.styleTableCell(cell)
            cell.accessoryType = .none
            cell.textLabel?.font = ClawTheme.font(16)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.textLabel?.numberOfLines = 0
        }
        contactUs.textLabel?.text = NSLocalizedString("支持方式未配置", comment: "Support unavailable")
        termsOfUse.textLabel?.text = NSLocalizedString("服务条款未配置", comment: "Terms unavailable")
        privacyPolicy.textLabel?.text = NSLocalizedString("隐私政策未配置", comment: "Privacy policy unavailable")
        appVersion.textColor = ClawTheme.muted
        serviceNameLabel.textColor = ClawTheme.muted
        serviceLinkLabel.textColor = ClawTheme.muted
        serverAddressLabel.textColor = ClawTheme.muted
        logoView.layer.cornerRadius = 16
        logoView.layer.cornerCurve = .continuous
        logoView.clipsToBounds = true
        UiUtils.setupTapRecognizer(
            forView: privacyPolicy,
            action: #selector(SettingsHelpViewController.privacyPolicyClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: contactUs,
            action: #selector(SettingsHelpViewController.contactUsClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: termsOfUse,
            action: #selector(SettingsHelpViewController.termsOfUseClicked),
            actionTarget: self)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let versionCode = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        self.appVersion.text = "\(version) (\(versionCode))"

        // No verified legal/support destination has been supplied for this release.
        // Do not treat the previous brand's domain as this service's published policy.

        // Logo.
        logoView.image = UIImage(named: "logo-ios")
        // Service name.
        serviceNameLabel.text = NSLocalizedString("CLAW OS", comment: "Product name")
        serviceLinkLabel.text = NSLocalizedString("连接信息仅用于诊断", comment: "Connection diagnostics description")
        // Server address.
        let (host, tls) = Tinode.getConnectionParams()
        serverAddressLabel.text = (tls ? "https://" : "http://") + host

        // Precompute content height.
        // Table is confitured as static cells. Can use simple loop.
        self.contentHeight = 0
        for i in 0..<tableView.numberOfSections {
            let numRows = tableView.numberOfRows(inSection: i)
            for j in 0..<numRows {
                let h = tableView(self.tableView, heightForRowAt: IndexPath(row: j, section: i))
                self.contentHeight += h > 0 ? h : SettingsHelpViewController.kDefaultRowHeight
            }
        }

        if SharedUtils.appId != nil {
            self.isUsingCustomBranding = true
        }
        self.poweredByView.isHidden = !isUsingCustomBranding
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 && indexPath.row == 0 { return 230 }
        return max(SettingsHelpViewController.kDefaultRowHeight, ceil(ClawTheme.font(16).lineHeight) + 24)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if isUsingCustomBranding {
            // Adjust "Powered by" view position.
            let topPadding = self.tableView.safeAreaInsets.top
            let bottomPadding = self.tableView.safeAreaInsets.bottom
            // Total space available below table content and the bottom.
            let height = tableView.frame.height - topPadding - bottomPadding - self.contentHeight
            // height < 0 means "Powered By" isn't visible.
            let h = height > 0 ? height : SettingsHelpViewController.kDefaultRowHeight
            if h >= SettingsHelpViewController.kDefaultRowHeight && poweredByView.frame.size.height != h {
                poweredByView.frame.size.height = h
            }
        }
    }

    @objc func termsOfUseClicked(sender: UITapGestureRecognizer) {
        UiUtils.showToast(message: NSLocalizedString("尚未提供已核实的服务条款，当前无法查看。", comment: "Terms unavailable"))
    }

    @objc func privacyPolicyClicked(sender: UITapGestureRecognizer) {
        UiUtils.showToast(message: NSLocalizedString("尚未提供已核实的隐私政策，当前无法查看。", comment: "Privacy policy unavailable"))
    }

    @objc func contactUsClicked(sender: UITapGestureRecognizer) {
        UiUtils.showToast(message: NSLocalizedString("支持方式尚未配置，请联系为你提供此应用的管理员。", comment: "Support unavailable"))
    }

    @objc private func showLicenses() {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "plist",
                                        subdirectory: "Settings.bundle"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let entries = dictionary["PreferenceSpecifiers"] as? [[String: Any]] else {
            UiUtils.showToast(message: NSLocalizedString("本机开源许可文件暂不可用。", comment: "License file unavailable"))
            return
        }
        let notices = entries.compactMap { entry -> String? in
            guard let text = entry["FooterText"] as? String, !text.isEmpty else { return nil }
            let name = entry["Title"] as? String ?? ""
            return name.isEmpty ? text : name + "\n\n" + text
        }
        guard !notices.isEmpty else {
            UiUtils.showToast(message: NSLocalizedString("本机开源许可文件暂不可用。", comment: "License file unavailable"))
            return
        }
        let controller = UIViewController()
        controller.title = NSLocalizedString("开源许可", comment: "Open source licenses")
        controller.view.backgroundColor = ClawTheme.background
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = ClawTheme.surface
        textView.textColor = ClawTheme.ink
        textView.font = ClawTheme.font(13, style: .footnote)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 16, bottom: 24, right: 16)
        textView.text = notices.joined(separator: "\n\n────────\n\n")
        controller.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor)
        ])
        navigationController?.pushViewController(controller, animated: true)
    }
}
