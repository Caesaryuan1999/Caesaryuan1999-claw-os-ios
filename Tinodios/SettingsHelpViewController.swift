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
    private var measuredWidth: CGFloat = 0
    private var measuredExplanationWidths = [CGFloat]()
    private var updatingExplanationHeights = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        title = NSLocalizedString("帮助与客服", comment: "Help settings title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("开源许可", comment: "Open source licenses"),
            style: .plain, target: self, action: #selector(showLicenses))
        view.accessibilityIdentifier = "claw.settings.help.screen"
        view.backgroundColor = ClawTheme.background
        ClawTheme.styleList(tableView, rowHeight: SettingsHelpViewController.kDefaultRowHeight)
        tableView.allowsSelection = false
        let helpCells: [UITableViewCell] = [contactUs, termsOfUse, privacyPolicy]
        helpCells.forEach { cell in
            ClawTheme.styleTableCell(cell)
            cell.accessoryType = .none
            cell.selectionStyle = .none
            cell.imageView?.image = nil
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = .staticText
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.lineBreakMode = .byWordWrapping
        }
        contactUs.textLabel?.text = NSLocalizedString("客服服务暂未开通", comment: "Support unavailable") + "\n" +
            NSLocalizedString("客服将协助处理账号使用问题。服务开通前，暂不接收留言。", comment: "Support unavailable explanation")
        termsOfUse.textLabel?.text = NSLocalizedString("服务条款暂不可用", comment: "Terms unavailable")
        privacyPolicy.textLabel?.text = NSLocalizedString("隐私政策暂不可用", comment: "Privacy policy unavailable")
        helpCells.forEach { $0.accessibilityLabel = $0.textLabel?.text }
        updateExplanationFonts()
        appVersion.textColor = ClawTheme.muted
        serviceNameLabel.textColor = ClawTheme.muted
        serviceLinkLabel.textColor = ClawTheme.muted
        serviceLinkLabel.accessibilityTraits = .staticText
        serverAddressLabel.textColor = ClawTheme.muted
        logoView.layer.cornerRadius = 16
        logoView.layer.cornerCurve = .continuous
        logoView.clipsToBounds = true

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
        if indexPath.section == 0, (1...3).contains(indexPath.row) {
            let cells: [UITableViewCell?] = [contactUs, termsOfUse, privacyPolicy]
            let cell = cells[indexPath.row - 1]
            let width = explanationTextWidth(in: cell)
            let height = cell?.textLabel?.sizeThatFits(
                CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height ?? 0
            return max(SettingsHelpViewController.kDefaultRowHeight, ceil(height) + 24)
        }
        return max(SettingsHelpViewController.kDefaultRowHeight, ceil(ClawTheme.font(16).lineHeight) + 24)
    }

    private func explanationTextWidth(in cell: UITableViewCell?) -> CGFloat {
        // Static storyboard cells retain UIKit's actual text inset. A table-wide
        // estimate cannot substitute for that label width once it is laid out.
        if let width = cell?.textLabel?.bounds.width, width.isFinite, width > 0 { return width }
        return max(1, tableView.bounds.width - tableView.safeAreaInsets.left - tableView.safeAreaInsets.right - 40)
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell,
                            forRowAt indexPath: IndexPath) {
        if indexPath.section == 0, (1...3).contains(indexPath.row) {
            // An offscreen static cell can receive its real text width later.
            // Request layout; do not start a nested table update while displaying it.
            tableView.setNeedsLayout()
        }
    }

    private func updateExplanationFonts() {
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 16), compatibleWith: traitCollection)
        [contactUs, termsOfUse, privacyPolicy].forEach { $0?.textLabel?.font = font }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded, previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        updateExplanationFonts()
        tableView.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = tableView.bounds.width - tableView.safeAreaInsets.left - tableView.safeAreaInsets.right
        let textWidths = [contactUs, termsOfUse, privacyPolicy].map { explanationTextWidth(in: $0) }
        if !updatingExplanationHeights && (width != measuredWidth || textWidths != measuredExplanationWidths) {
            measuredWidth = width
            measuredExplanationWidths = textWidths
            updatingExplanationHeights = true
            tableView.beginUpdates(); tableView.endUpdates()
            updatingExplanationHeights = false
        }

        if isUsingCustomBranding {
            // Adjust "Powered by" view position.
            contentHeight = (0..<tableView.numberOfSections).reduce(CGFloat(0)) { total, section in
                total + (0..<tableView.numberOfRows(inSection: section)).reduce(CGFloat(0)) {
                    $0 + tableView.rectForRow(at: IndexPath(row: $1, section: section)).height
                }
            }
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
