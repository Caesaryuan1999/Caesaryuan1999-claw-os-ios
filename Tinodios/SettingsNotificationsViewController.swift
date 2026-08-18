//
//  SettingsNotificationsViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import TinodeSDK
import TinodiosDB
import UIKit
import UserNotifications

class SettingsNotificationsViewController: UITableViewController {
    // Kept optional because older storyboards still contain these connections.
    @IBOutlet weak var incognitoModeSwitch: UISwitch?
    @IBOutlet weak var sendReadReceiptsSwitch: UISwitch?
    @IBOutlet weak var sendTypingNotificationsSwitch: UISwitch?

    private enum Section: Int, CaseIterable {
        case status
        case messages
        case delivery
        case privacy
    }

    private enum PreferenceTag: Int {
        case privateMessages = 100
        case groupMessages
        case calls
        case preview
        case vibration
        case incognito
        case readReceipts
        case typing
    }

    private struct RowModel {
        let title: String
        let subtitle: String?
        let symbol: String
        let tag: PreferenceTag?
        let preferenceKey: String?
    }

    private weak var me: DefaultMeTopic?
    private var notificationsAuthorized = false

    private func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "CLAW OS notification settings")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAuthorizationStatus()
        tableView.reloadData()
    }

    private func setup() {
        title = text("notification_settings_title")
        me = Cache.tinode.getMeTopic()

        let premiumTable = UITableView(frame: .zero, style: .insetGrouped)
        premiumTable.backgroundColor = ClawTheme.background
        premiumTable.separatorColor = ClawTheme.border
        premiumTable.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 16)
        premiumTable.sectionHeaderHeight = 38
        premiumTable.sectionFooterHeight = 12
        premiumTable.keyboardDismissMode = .onDrag
        premiumTable.dataSource = self
        premiumTable.delegate = self
        tableView = premiumTable
    }

    private func rows(in section: Section) -> [RowModel] {
        switch section {
        case .status:
            return []
        case .messages:
            return [
                RowModel(title: text("private_messages"), subtitle: text("private_messages_summary"), symbol: "message",
                         tag: .privateMessages, preferenceKey: SharedUtils.kClawPrefPrivateMessageNotifications),
                RowModel(title: text("group_messages"), subtitle: text("group_messages_summary"), symbol: "person.2",
                         tag: .groupMessages, preferenceKey: SharedUtils.kClawPrefGroupMessageNotifications),
                RowModel(title: text("call_reminders"), subtitle: text("call_reminders_summary"), symbol: "phone",
                         tag: .calls, preferenceKey: SharedUtils.kClawPrefCallNotifications),
                RowModel(title: text("message_preview"), subtitle: text("message_preview_summary"), symbol: "text.bubble",
                         tag: .preview, preferenceKey: SharedUtils.kClawPrefMessagePreview)
            ]
        case .delivery:
            return [
                RowModel(title: text("notification_sound"), subtitle: text("notification_sound_value"), symbol: "speaker.wave.2",
                         tag: nil, preferenceKey: nil),
                RowModel(title: text("in_app_vibration"), subtitle: text("in_app_vibration_summary"), symbol: "iphone.radiowaves.left.and.right",
                         tag: .vibration, preferenceKey: SharedUtils.kClawPrefInAppVibration)
            ]
        case .privacy:
            return [
                RowModel(title: text("incognito_mode"), subtitle: text("incognito_mode_summary"), symbol: "eye.slash",
                         tag: .incognito, preferenceKey: nil),
                RowModel(title: text("read_receipts"), subtitle: text("read_receipts_summary"), symbol: "checkmark.message",
                         tag: .readReceipts, preferenceKey: SharedUtils.kTinodePrefReadReceipts),
                RowModel(title: text("typing_status"), subtitle: text("typing_status_summary"), symbol: "ellipsis.message",
                         tag: .typing, preferenceKey: SharedUtils.kTinodePrefTypingNotifications)
            ]
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        return section == .status ? 1 : rows(in: section).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .messages: return text("message_notifications")
        case .delivery: return text("alert_style")
        case .privacy: return text("privacy_and_receipts")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = ClawTheme.ink
        header.textLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == Section.status.rawValue ? 90 : 67
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        if section == .status {
            return statusCell()
        }

        let row = rows(in: section)[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = ClawTheme.surface
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = ClawTheme.ink
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cell.detailTextLabel?.text = row.subtitle
        cell.detailTextLabel?.textColor = ClawTheme.muted
        cell.detailTextLabel?.font = .systemFont(ofSize: 12, weight: .regular)
        cell.imageView?.image = ClawTheme.symbol(row.symbol, pointSize: 19, weight: .medium)
        cell.imageView?.tintColor = ClawTheme.primary
        cell.selectionStyle = row.tag == nil ? .default : .none

        if let tag = row.tag {
            let control = UISwitch()
            control.onTintColor = ClawTheme.primary
            control.tag = tag.rawValue
            control.isOn = switchValue(for: tag, preferenceKey: row.preferenceKey)
            control.accessibilityLabel = row.title
            control.addTarget(self, action: #selector(preferenceSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = control
        } else {
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    private func statusCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = ClawTheme.brandSoft
        cell.textLabel?.text = notificationsAuthorized ? text("notification_status_enabled") : text("notification_status_disabled")
        cell.textLabel?.textColor = ClawTheme.ink
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        cell.detailTextLabel?.text = notificationsAuthorized ? text("notification_status_enabled_summary") : text("notification_status_disabled_summary")
        cell.detailTextLabel?.textColor = ClawTheme.muted
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.imageView?.image = ClawTheme.symbol(notificationsAuthorized ? "bell.badge.fill" : "bell.slash.fill",
                                                pointSize: 22, weight: .semibold)
        cell.imageView?.tintColor = ClawTheme.primary
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityTraits.insert(.button)
        cell.accessibilityLabel = [cell.textLabel?.text, cell.detailTextLabel?.text].compactMap { $0 }.joined(separator: ", ")
        return cell
    }

    private func switchValue(for tag: PreferenceTag, preferenceKey: String?) -> Bool {
        if tag == .incognito {
            return me?.isMuted ?? false
        }
        guard let preferenceKey = preferenceKey else { return false }
        return SharedUtils.kAppDefaults.bool(forKey: preferenceKey)
    }

    @objc private func preferenceSwitchChanged(_ sender: UISwitch) {
        guard let tag = PreferenceTag(rawValue: sender.tag) else { return }
        switch tag {
        case .privateMessages:
            setPreference(SharedUtils.kClawPrefPrivateMessageNotifications, value: sender.isOn)
        case .groupMessages:
            setPreference(SharedUtils.kClawPrefGroupMessageNotifications, value: sender.isOn)
        case .calls:
            setPreference(SharedUtils.kClawPrefCallNotifications, value: sender.isOn)
        case .preview:
            setPreference(SharedUtils.kClawPrefMessagePreview, value: sender.isOn)
        case .vibration:
            setPreference(SharedUtils.kClawPrefInAppVibration, value: sender.isOn)
        case .readReceipts:
            setPreference(SharedUtils.kTinodePrefReadReceipts, value: sender.isOn)
        case .typing:
            setPreference(SharedUtils.kTinodePrefTypingNotifications, value: sender.isOn)
        case .incognito:
            updateIncognito(sender)
            return
        }

        if sender.isOn && (tag == .privateMessages || tag == .groupMessages || tag == .calls) {
            requestSystemAuthorization()
        }
    }

    private func setPreference(_ key: String, value: Bool) {
        SharedUtils.kAppDefaults.set(value, forKey: key)
    }

    private func updateIncognito(_ sender: UISwitch) {
        guard let me = me else {
            sender.setOn(false, animated: true)
            UiUtils.showToast(message: text("account_status_not_ready"))
            return
        }
        let requested = sender.isOn
        me.updateMuted(muted: requested).then(
            onSuccess: UiUtils.ToastSuccessHandler,
            onFailure: { err in
                DispatchQueue.main.async { sender.setOn(!requested, animated: true) }
                return UiUtils.ToastFailureHandler(err: err)
            }).thenFinally({ [weak self] in
                DispatchQueue.main.async { self?.tableView.reloadData() }
            })
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        if section == .status {
            notificationsAuthorized ? openSystemSettings() : requestSystemAuthorization()
        } else if section == .delivery && indexPath.row == 0 {
            openSystemSettings()
        }
    }

    private func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let enabled = Self.hasUsableMessageAuthorization(settings)
            DispatchQueue.main.async {
                self?.notificationsAuthorized = enabled
                self?.tableView.reloadSections(IndexSet(integer: Section.status.rawValue), with: .none)
            }
        }
    }

    private static func hasUsableMessageAuthorization(_ settings: UNNotificationSettings) -> Bool {
        let authorizationGranted: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationGranted = true
        default:
            authorizationGranted = false
        }
        guard authorizationGranted else { return false }

        // Authorization alone is not enough: users can keep permission granted
        // while disabling the actual alert/banner channel in iOS Settings.
        return settings.alertSetting == .enabled
            && settings.notificationCenterSetting == .enabled
    }

    private func requestSystemAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self?.refreshAuthorizationStatus()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // Legacy storyboard actions remain valid for older installed storyboard resources.
    @IBAction func incognitoModeClicked(_ sender: Any) {
        if let control = sender as? UISwitch { updateIncognito(control) }
    }

    @IBAction func readReceiptsClicked(_ sender: Any) {
        guard let control = sender as? UISwitch else { return }
        setPreference(SharedUtils.kTinodePrefReadReceipts, value: control.isOn)
    }

    @IBAction func typingNotificationsClicked(_ sender: Any) {
        guard let control = sender as? UISwitch else { return }
        setPreference(SharedUtils.kTinodePrefTypingNotifications, value: control.isOn)
    }
}
