//
//  Utils.swift
//  Tinodios
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import Foundation
import UIKit
import Kingfisher
import MobileCoreServices
import PhoneNumberKit
import TinodeSDK
import TinodiosDB

enum ClawTheme {
    enum GroupedCellPosition {
        case single
        case first
        case middle
        case last
    }

    // R3.D1 semantic colors. UIKit resolves both appearances at display time.
    private static func color(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 0xff) / 255,
                           green: CGFloat((rgb >> 8) & 0xff) / 255,
                           blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
        }
    }

    static let primary = color(light: 0x006F64, dark: 0x72D9BF)
    static let onBrand = color(light: 0xFFFFFF, dark: 0x102D24)
    static let primaryPressed = primary.withAlphaComponent(0.85)
    static let accent = primary
    static let success = primary
    static let warning = UIColor(red: 255 / 255, green: 176 / 255, blue: 32 / 255, alpha: 1)
    static let danger = color(light: 0xA83236, dark: 0xFFB4AC)
    static let dangerSoft = danger.withAlphaComponent(0.12)
    static let brandSoft = color(light: 0xE4EFEB, dark: 0x293D35)
    static let background = color(light: 0xF4F6F3, dark: 0x101B19)
    static let surface = color(light: 0xFFFFFF, dark: 0x1B2926)
    static let surfaceMuted = brandSoft
    static let border = color(light: 0xD9E3DE, dark: 0x3B5047)
    static let ink = color(light: 0x182E2D, dark: 0xEDF5F0)
    static let muted = color(light: 0x566865, dark: 0xA6B9B1)

    static let inputRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 12
    static let cardRadius: CGFloat = 16
    static let cornerRadius: CGFloat = cardRadius
    static let touchTarget: CGFloat = 48

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular,
                     style: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    static let iconSmall: CGFloat = 18
    static let iconCompact: CGFloat = 20
    static let iconStandard: CGFloat = 24

    static func applyGlobalAppearance() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = surface
        navigationAppearance.shadowColor = border
        navigationAppearance.titleTextAttributes = [.foregroundColor: ink]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: ink]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = navigationAppearance
        navigationBar.compactAppearance = navigationAppearance
        navigationBar.scrollEdgeAppearance = navigationAppearance
        navigationBar.tintColor = primary

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = surface
        tabAppearance.shadowColor = border
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabAppearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = tabAppearance
        }
        tabBar.tintColor = primary

        UISwitch.appearance().onTintColor = primary
        UITableView.appearance().tintColor = primary
        UITableView.appearance().separatorColor = border
    }

    static func stylePrimaryButton(_ button: UIButton) {
        button.backgroundColor = primary
        button.tintColor = onBrand
        button.setTitleColor(onBrand, for: .normal)
        button.setTitleColor(onBrand.withAlphaComponent(0.6), for: .disabled)
        button.titleLabel?.font = font(16, weight: .semibold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.textAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.layer.cornerRadius = buttonRadius
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
    }

    static func styleSecondaryButton(_ button: UIButton) {
        button.backgroundColor = .clear
        button.tintColor = primary
        button.setTitleColor(primary, for: .normal)
        button.titleLabel?.font = font(16, weight: .medium)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    static func styleTextField(_ textField: UITextField) {
        textField.backgroundColor = surface
        textField.textColor = ink
        textField.tintColor = primary
        textField.borderStyle = .none
        textField.layer.borderWidth = 1
        textField.layer.borderColor = border.cgColor
        textField.layer.cornerRadius = inputRadius
        textField.layer.cornerCurve = .continuous
        textField.clipsToBounds = true
        if textField.leftView == nil {
            textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
            textField.leftViewMode = .always
        }
    }

    static func styleTextView(_ textView: UITextView) {
        textView.backgroundColor = surface
        textView.textColor = ink
        textView.tintColor = primary
        textView.layer.borderWidth = 1
        textView.layer.borderColor = border.cgColor
        textView.layer.cornerRadius = inputRadius
        textView.layer.cornerCurve = .continuous
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.clipsToBounds = true
    }

    static func styleTableCell(_ cell: UITableViewCell, destructive: Bool = false) {
        cell.backgroundColor = surface
        cell.textLabel?.textColor = destructive ? danger : ink
        cell.detailTextLabel?.textColor = muted
        cell.imageView?.tintColor = destructive ? danger : primary
        cell.imageView?.contentMode = .center
        cell.imageView?.clipsToBounds = false
        cell.tintColor = primary
    }

    static func styleTableCell(_ cell: UITableViewCell, symbolName: String,
                               destructive: Bool = false) {
        styleTableCell(cell, destructive: destructive)
        cell.imageView?.image = symbol(symbolName, pointSize: iconStandard, weight: .medium)
        cell.imageView?.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: iconStandard,
            weight: .medium,
            scale: .medium)
        cell.imageView?.contentMode = .center
    }

    static func groupedPosition(for row: Int, visibleRows: [Int]) -> GroupedCellPosition {
        guard visibleRows.count > 1 else { return .single }
        if row == visibleRows.first { return .first }
        if row == visibleRows.last { return .last }
        return .middle
    }

    static func styleGroupedCell(_ cell: UITableViewCell,
                                 position: GroupedCellPosition,
                                 destructive: Bool = false,
                                 backgroundColor: UIColor = surface) {
        let normal = ClawGroupedCellBackgroundView(position: position, color: backgroundColor)
        let selected = ClawGroupedCellBackgroundView(position: position, color: brandSoft)
        cell.backgroundColor = .clear
        cell.backgroundView = normal
        cell.selectedBackgroundView = selected
        cell.textLabel?.textColor = destructive ? danger : ink
        cell.detailTextLabel?.textColor = muted
        cell.preservesSuperviewLayoutMargins = false
        cell.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        cell.separatorInset = position == .last || position == .single
            ? UIEdgeInsets(top: 0, left: 0, bottom: 0, right: .greatestFiniteMagnitude)
            : UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 18)
    }

    static func normalizeIconButtons(in rootView: UIView) {
        if let button = rootView as? UIButton, button.currentImage != nil {
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center
            button.imageView?.contentMode = .scaleAspectFit
            button.imageView?.clipsToBounds = false
            button.imageEdgeInsets = .zero
            if button.currentTitle == nil {
                button.contentEdgeInsets = .zero
            }
        }
        rootView.subviews.forEach { normalizeIconButtons(in: $0) }
    }

    static func makeStatusHeader(title: String, detail: String, symbolName: String) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 124))
        container.backgroundColor = .clear

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = brandSoft
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous

        let iconBox = UIView()
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.backgroundColor = primary.withAlphaComponent(0.10)
        iconBox.layer.cornerRadius = 14
        iconBox.layer.cornerCurve = .continuous

        let icon = UIImageView(image: symbol(symbolName, pointSize: iconStandard, weight: .medium))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = primary
        icon.contentMode = .center
        iconBox.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = ink
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 1

        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = detail
        detailLabel.textColor = muted
        detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailLabel.numberOfLines = 2

        card.addSubview(iconBox)
        card.addSubview(titleLabel)
        card.addSubview(detailLabel)
        container.addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            iconBox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconBox.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 48),
            iconBox.heightAnchor.constraint(equalToConstant: 48),
            icon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: iconStandard),
            icon.heightAnchor.constraint(equalToConstant: iconStandard),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16)
        ])
        return container
    }

    static func symbol(_ name: String, pointSize: CGFloat = iconStandard,
                       weight: UIImage.SymbolWeight = .regular) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: .medium)
        return UIImage(systemName: name, withConfiguration: configuration)
    }

    static func styleIconButton(_ button: UIButton, symbolName: String,
                                pointSize: CGFloat = iconCompact,
                                tintColor: UIColor = primary) {
        button.setImage(symbol(symbolName, pointSize: pointSize), for: .normal)
        button.tintColor = tintColor
        button.imageView?.contentMode = .scaleAspectFit
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.imageEdgeInsets = .zero
        button.contentEdgeInsets = .zero
        button.clipsToBounds = false
    }

    static func styleRoundedIconButton(_ button: UIButton, symbolName: String,
                                       selected: Bool = false) {
        styleIconButton(button, symbolName: symbolName, pointSize: iconCompact,
                        tintColor: selected ? onBrand : primary)
        button.backgroundColor = selected ? primary : brandSoft
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
    }

    static func styleSearchBar(_ searchBar: UISearchBar) {
        searchBar.tintColor = primary
        searchBar.barTintColor = background
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.backgroundColor = surfaceMuted
        searchBar.searchTextField.textColor = ink
        searchBar.searchTextField.tintColor = primary
        searchBar.searchTextField.layer.cornerRadius = inputRadius
        searchBar.searchTextField.layer.cornerCurve = .continuous
        searchBar.searchTextField.clipsToBounds = true
        searchBar.searchTextField.leftView?.tintColor = muted
        searchBar.searchTextField.clearButtonMode = .whileEditing
    }

    static func styleList(_ tableView: UITableView, rowHeight: CGFloat = 76) {
        tableView.backgroundColor = background
        tableView.separatorColor = border
        tableView.rowHeight = rowHeight
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 18)
        tableView.sectionHeaderHeight = 38
        tableView.sectionFooterHeight = 12
        tableView.keyboardDismissMode = .onDrag
    }

    static func styleCard(_ view: UIView, radius: CGFloat = cardRadius) {
        view.backgroundColor = surface
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = border.cgColor
        view.clipsToBounds = true
    }

    static func styleCallControl(_ button: UIButton, symbolName: String,
                                 backgroundColor: UIColor = surface,
                                 tintColor: UIColor = primary) {
        styleIconButton(button, symbolName: symbolName, pointSize: 21, tintColor: tintColor)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 28
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.adjustsImageWhenHighlighted = true
    }
}

private final class ClawGroupedCellBackgroundView: UIView {
    private let fillView = UIView()
    private let position: ClawTheme.GroupedCellPosition

    init(position: ClawTheme.GroupedCellPosition, color: UIColor) {
        self.position = position
        super.init(frame: .zero)
        backgroundColor = .clear
        fillView.backgroundColor = color
        fillView.layer.cornerCurve = .continuous
        addSubview(fillView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillView.frame = bounds.inset(by: UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18))
        fillView.layer.cornerRadius = (position == .middle) ? 0 : ClawTheme.cardRadius
        switch position {
        case .single:
            fillView.layer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
        case .first:
            fillView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .middle:
            fillView.layer.maskedCorners = []
        case .last:
            fillView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
    }
}

public class Utils {
    public static let kTopicUriPrefix = "tinode:topic/"

    static var phoneNumberKit: PhoneNumberUtility = {
        return PhoneNumberUtility()
    }()

    // Calculate difference between two arrays of messages. Returns a tuple of insertion indexes and deletion indexes.
    // First the deletion indexes are applied to the old array. Then insertions are applied to the remaining array.
    // Indexes should be applied in descending order.
    public static func diffMessageArray(sortedOld old: [Message], sortedNew new: [Message]) -> (inserted: [Int], removed: [Int], mutated: [Int]) {
        if old.isEmpty && new.isEmpty {
            return (inserted: [], removed: [], mutated: [])
        }
        if old.isEmpty {
            return (inserted: Array(0 ..< new.count), removed: [], mutated: Array(0 ..< new.count))
        }
        if new.isEmpty {
            return (inserted: [], removed: Array(0 ..< old.count), mutated: [])
        }

        var removed: [Int] = []
        var inserted: [Int] = []
        var mutated: [Int] = []

        // Match old array against the new array to separate removed items from inserted.
        var o = 0, n = 0
        while o < old.count || n < new.count {
            if o == old.count || (n < new.count && old[o].seqId > new[n].seqId) {
                // Present in new, missing in old: added
                inserted.append(n)
                if mutated.last ?? -1 != n {
                    mutated.append(n)
                }
                n += 1

            } else if n == new.count || old[o].seqId < new[n].seqId {
                // Present in old, missing in new: removed
                removed.append(o)
                if mutated.last ?? -1 != n && n < new.count {
                    // Appending n, not o because mutated is an index agaist the new data.
                    mutated.append(n)
                }
                o += 1

            } else {
                // present in both
                if o < old.count && n < new.count && !old[o].equals(new[n]) {
                    mutated.append(n)
                }
                if o < old.count {
                    o += 1
                }
                if n < new.count {
                    n += 1
                }
            }
        }

        return (inserted: inserted, removed: removed, mutated: mutated)
    }

    public static func isValidTag(tag: String) -> Bool {
        let minTagLength = Cache.tinode.getServerLimit(for: Tinode.kMinTagLength, withDefault: UiUtils.kMinTagLength)
        let maxTagLength = Cache.tinode.getServerLimit(for: Tinode.kMaxTagLength, withDefault: UiUtils.kMaxTagLength)
        return tag.count >= minTagLength && tag.count <= maxTagLength
    }

    public static func uniqueFilename(forMime mime: String?) -> String {
        let mimeType: CFString = (mime ?? "application/octet-stream") as CFString
        var ext: String?
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, nil)?.takeUnretainedValue() {
            ext = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension)?.takeUnretainedValue() as String?
        }
        return ProcessInfo.processInfo.globallyUniqueString + "." + (ext ?? "bin")
    }

    public static func mimeForUrl(url: URL, ifMissing: String = "application/octet-stream") -> String {
        if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
            let unmanaged = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)
            return unmanaged?.takeRetainedValue() as String? ?? ifMissing
        }
        return ifMissing
    }

    public static func fetchTopics(archived: Bool) -> [DefaultComTopic]? {
        return Cache.tinode.getFilteredTopics(filter: {(topic: TopicProto) in
            return topic.topicType.matches(TopicType.user) && topic.isArchived == archived && topic.isJoiner
        })?.map {
            // Must succeed.
            $0 as! DefaultComTopic
        }
    }

    // Creates a URL out of Tinode ref.
    public static func tinodeResourceUrl(from ref: String) -> URL? {
        let u = URL(string: ref, relativeTo: Cache.tinode.baseURL(useWebsocketProtocol: false))
        return u
    }

    // Initializes a download for a resource (typically, an image) from the provided url.
    public static func fetchTinodeResource(from url: URL?) -> PromisedReply<UIImage> {
        let modifier = AnyModifier { request in
            var request = request
            LargeFileHelper.addCommonHeaders(to: &request, using: Cache.tinode)
            return request
        }
        let p = PromisedReply<UIImage>()
        KingfisherManager.shared.retrieveImage(with: url!.downloadURL, options: [.requestModifier(modifier)], completionHandler: { result in
            switch result {
            case .success(let value):
                try? p.resolve(result: value.image)
            case .failure(let error):
                try? p.reject(error: error)
            }
        })
        return p
    }

    public static func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: String.Encoding.ascii)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")

        guard let qrcode = filter.outputImage else { return nil }

        // QR code is very small. Scaling it up without smoothing.
        let scaledImageSize = qrcode.extent.size.applying(CGAffineTransform(scaleX: 3, y: 3))
        UIGraphicsBeginImageContext(scaledImageSize)
        let scaledContext = UIGraphicsGetCurrentContext()!
        scaledContext.interpolationQuality = .none
        UIImage(ciImage: qrcode).draw(in: CGRect(origin: .zero, size: scaledImageSize))
        return UIGraphicsGetImageFromCurrentImageContext()!
    }

    private static let kTelRegex = try! NSRegularExpression(pattern: #"^(?:\+?(\d{1,3}))?[- (.]*(\d{3})[- ).]*(\d{3})[- .]*(\d{2})[- .]*(\d{2})?$"#)
    private static let kTelReplacementRegex = try! NSRegularExpression(pattern: "[- ().]*")
    /// Checks (loosely) if the given string is a phone. If so, returns the phone number in a format
    /// as close to E.164 as possible.
    public static func asPhone(_ val: String) -> String? {
        let val = val.trimmingCharacters(in: .whitespacesAndNewlines)
        if kTelRegex.firstMatch(in: val, options: [], range: NSRange(location: 0, length: val.utf16.count)) != nil {
            return kTelReplacementRegex.stringByReplacingMatches(in: val, range: NSRange(location: 0, length: val.utf16.count), withTemplate: "")
        }
        return nil
    }

    private static let kEmailRegex = try! NSRegularExpression(pattern: #"^[a-z0-9_.+-]+@[a-z0-9-]+(\\.[a-z0-9-]+)+$"#)
     /// Checks (loosely) if the given string is an email. If so returns the email.
    public static func asEmail(_ val: String) -> String? {
        let val = val.trimmingCharacters(in: .whitespacesAndNewlines)
        if kEmailRegex.firstMatch(in: val, options: [], range: NSRange(location: 0, length: val.utf16.count)) != nil {
            return val
        }
        return nil
    }
}

// Per
// https://medium.com/over-engineering/a-background-repeating-timer-in-swift-412cecfd2ef9
class RepeatingTimer {
    let timeInterval: TimeInterval
    init(timeInterval: TimeInterval) {
        self.timeInterval = timeInterval
    }
    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + self.timeInterval, repeating: self.timeInterval)
        t.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
        })
        return t
    }()
    var eventHandler: (() -> Void)?
    public enum State {
        case suspended
        case resumed
    }
    public var state: State = .suspended
    deinit {
        timer.setEventHandler {}
        timer.cancel()
        // If the timer is suspended, calling cancel without resuming
        // triggers a crash. This is documented here
        // https://forums.developer.apple.com/thread/15902
        resume()
        eventHandler = nil
    }

    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }

    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }
}

class RelativeDateFormatter {
    // DateFormatter is thread safe, OK to keep a copy.
    static let shared = RelativeDateFormatter()

    private let formatter = DateFormatter()

    func dateOnly(from date: Date?, style: DateFormatter.Style = .medium) -> String {
        guard let date = date else { return NSLocalizedString("Never ??:??", comment: "Invalid date") }

        formatter.timeStyle = .none
        formatter.dateStyle = style
        switch true {
        case Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date):
            // "today", "yesterday"
            formatter.doesRelativeDateFormatting = true
        case Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear):
            // day of the week "Wednesday", "Friday" etc
            formatter.dateFormat = "EEEE"
        default:
            // All other dates: "Mar 15, 2019"
            break
        }
        return formatter.string(from: date)
    }

    func timeOnly(from date: Date?, style: DateFormatter.Style = .short) -> String {
        guard let date = date else { return "??:??" }

        formatter.timeStyle = style
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    // Incrementally longer formatting of a date.
    func shortDate(from date: Date?) -> String {
        guard let date = date else { return NSLocalizedString("Never ??:??", comment: "Invalid date") }

        let now = Date()
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            if Calendar.current.isDate(date, equalTo: now, toGranularity: .day) {
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                return formatter.string(from: date)
            } else {
                formatter.timeStyle = .short
                formatter.dateStyle = .short
                return formatter.string(from: date)
            }
        }

        formatter.timeStyle = .medium
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

extension URL {
    public func extractQueryParam(named name: String) -> String? {
        let components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == name })?.value
    }

    // Attempt to convert the given URL to a relative URL using 'from' as the base.
    func relativize(from base: URL) -> String {
        // Ensure that both URLs share the scheme (protocol) and authority:
        guard self.scheme == base.scheme && self.host == base.host && self.port == base.port &&
                self.user == base.user && self.password == base.password else {
            return self.absoluteString
        }

        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self.absoluteString
        }

        return "\(components.path)?\(components.query ?? "")"
    }
}

extension UIFont {
    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return UIFont(descriptor: descriptor!, size: 0) // size 0 means keep the size as it is
    }
}

extension StoredMessage {
    static var previewFormatter: AbstractFormatter?

    /// Generate and cache NSAttributedString representation of Drafty content.
    func attributedContent(fitIn size: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        guard cachedContent == nil else { return cachedContent }
        if !isDeleted {
            guard let content = content else { return nil }
            cachedContent = FullFormatter(defaultAttributes: attributes ?? [:]).toAttributed(content, fitIn: size)
        } else {
            cachedContent = StoredMessage.contentDeletedMessage(withAttributes: attributes)
        }
        return cachedContent
    }

    /// Generate and cache NSAttributedString preview of Drafty content.
    func attributedPreview(fitIn size: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        guard cachedPreview == nil else { return cachedPreview }
        if !isDeleted {
            guard var content = content else { return nil }
            if StoredMessage.previewFormatter == nil {
                StoredMessage.previewFormatter = PreviewFormatter(defaultAttributes: [:])
            }
            content = content.preview(previewLen: UiUtils.kPreviewLength)
            cachedPreview = StoredMessage.previewFormatter!.toAttributed(content, fitIn: size)
        } else {
            cachedPreview = StoredMessage.contentDeletedMessage(withAttributes: attributes)
        }
        return cachedPreview
    }

    /// Creates "content deleted" string with a small "blocked" icon.
    private static func contentDeletedMessage(withAttributes attr: [NSAttributedString.Key: Any]?) -> NSAttributedString {
        // Space is needed as a workaround for a bug in UIKit. The icon style is not applied if the icon is the first object in the attributed string.
        let second = NSMutableAttributedString(string: " ")
        second.beginEditing()

        // Add 'block' icon.
        let icon = NSTextAttachment()
        icon.image = UIImage(systemName: "nosign")?.withRenderingMode(.alwaysTemplate)
        // Make image smaller
        icon.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        second.append(NSAttributedString(attachment: icon))
        if let attr = attr {
            // apply tint color to image
            second.addAttributes(attr, range: NSRange(location: 0, length: second.length))
        }
        // Align image and text vertically per
        // https://stackoverflow.com/questions/47844721/vertically-aligning-nstextattachment-in-nsmutableattributedstring
        var textFont: UIFont = attr?[.font] as? UIFont ?? UIFont.systemFont(ofSize: 14)
        textFont = textFont.withSize(14)
        var newAttr: [NSAttributedString.Key: Any] = attr ?? [:]
        newAttr[.baselineOffset] = (icon.bounds.height - textFont.pointSize) / 2 - textFont.descender / 2
        newAttr[.font] = textFont
        second.append(NSAttributedString(string: "  ", attributes: newAttr))
        second.append(NSAttributedString(string: NSLocalizedString("消息已删除", comment: "Replacement for chat message with no content"), attributes: newAttr))
        second.endEditing()
        return second
    }

    // Returns true if message contains an inline image.
    var isVisualMedia: Bool {
        guard let ents = self.content?.entities else { return false }
        return ents.contains {
            ["IM", "VD"].contains($0.tp)
        }
    }
}

extension Date {
    var millisecondsSince1970: Int64 {
        return Int64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
}

extension TimeInterval {
    var asDurationString: String {
        return String(format: "%02d:%02d", Int(self / 60), Int(self.truncatingRemainder(dividingBy: 60)))
    }
}

extension Tinode {
    func getRequiredCredMethods(forAuthLevel authLevel: String) -> [String]? {
        guard case let .dict(allCred) = self.getServerParam(for: "reqCred") else {
            return nil
        }
        if let allMeth = allCred[authLevel], case let .array(meth) = allMeth {
            return meth.map { $0.asString() ?? "" }.filter { !$0.isEmpty }
        }
        return nil
    }
}

extension Character {
    var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else {
            return false
        }
        return firstScalar.properties.isEmoji && (unicodeScalars.count > 1 || firstScalar.value > 0x238C)
    }
}

extension String {
    var isEmojiOnly: Bool { !isEmpty && !contains { !$0.isEmoji } }
}

extension DefaultComTopic {
    // Returns true if the topic allows calls to be placed.
    var callsAllowed: Bool {
        let t = Cache.tinode
        // The user is allowed to post messages and
        // - for p2p topics, we have ice servers to establish communication via.
        // - for group topics, we have media server endpoint.
        return self.isWriter && (self.isP2PType && t.getServerParam(for: "iceServers") != nil)
            // || (self.isGrpType && t.getServerParam(for: "vcEndpoint") != nil))
    }
}

extension CGRect {
    // Splits self into two rectangles measuring `fraction` (between 0..1) from the specified edge
    func dividedIntegral(fraction: CGFloat, from fromEdge: CGRectEdge) -> (first: CGRect, second: CGRect) {
        let dimension: CGFloat

        switch fromEdge {
        case .minXEdge, .maxXEdge:
            dimension = self.size.width
        case .minYEdge, .maxYEdge:
            dimension = self.size.height
        }

        let distance = (dimension * fraction).rounded(.up)
        var slices = self.divided(atDistance: distance, from: fromEdge)

        switch fromEdge {
        case .minXEdge, .maxXEdge:
            slices.remainder.origin.x += 1
            slices.remainder.size.width -= 1
        case .minYEdge, .maxYEdge:
            slices.remainder.origin.y += 1
            slices.remainder.size.height -= 1
        }

        return (first: slices.slice, second: slices.remainder)
    }
}

extension Array where Element: Comparable {
    // Compare arrays without regard for element order.
    func equals(_ other: [Element]?) -> Bool {
        guard let other = other else {
            return false
        }
        return self.count == other.count && self.sorted() == other.sorted()
    }
}

enum ClawAuthInput {
    static let minPasswordLength = 6
    static let inviteCredentialMethod = "invite"

    static func accountNameForSubmit(_ value: String?) -> String {
        return (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isAccountNameValid(_ value: String?) -> Bool {
        guard let value = value, !value.isEmpty else { return false }
        return value.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    static func passwordForSubmit(_ value: String?) -> String {
        return value ?? ""
    }

    static func isPasswordValid(_ value: String?) -> Bool {
        return passwordForSubmit(value).count >= minPasswordLength
    }

    static func inviteCodeForSubmit(_ value: String?) -> String {
        let raw = value ?? ""
        let payload = raw.filter { !$0.isWhitespace && $0 != "-" }.uppercased()
        let stripped = payload.hasPrefix("CLAW") ? String(payload.dropFirst(4)) : payload
        guard !stripped.isEmpty else { return "" }

        var out = "CLAW"
        for (idx, ch) in stripped.enumerated() {
            if idx % 4 == 0 {
                out.append("-")
            }
            out.append(ch)
        }
        return out
    }
}

enum ClawAuthErrorMessages {
    static func loginMessage(for error: Error) -> String {
        if let tinodeError = error as? TinodeError,
           case .serverResponseError(let code, _, _) = tinodeError {
            switch code {
            case 401:
                return NSLocalizedString("账号名或密码错误", comment: "Invalid login credentials")
            case 403:
                return NSLocalizedString("服务器拒绝了登录请求，请检查连接设置", comment: "Login forbidden")
            case 429:
                return NSLocalizedString("登录尝试过于频繁，请稍后重试", comment: "Login rate limited")
            case 500...599:
                return NSLocalizedString("服务器暂时不可用，请稍后重试", comment: "Login server error")
            default:
                break
            }
        }
        return networkMessage(for: error,
                              fallback: NSLocalizedString("登录失败，请检查账号名、密码和网络连接", comment: "Generic login failure"))
    }

    static func signUpMessage(for error: Error) -> String {
        return networkMessage(for: error,
                              fallback: NSLocalizedString("注册失败，请检查账号名、密码、邀请码和网络连接", comment: "Generic registration failure"))
    }

    static func passwordChangeMessage(for error: Error) -> String {
        if let tinodeError = error as? TinodeError,
           case .serverResponseError(let code, _, _) = tinodeError,
           code == 401 || code == 403 {
            return NSLocalizedString("身份验证已失效，请重新登录后修改密码", comment: "Password change authentication failure")
        }
        return networkMessage(for: error,
                              fallback: NSLocalizedString("密码修改失败，请稍后重试", comment: "Generic password change failure"))
    }

    private static func networkMessage(for error: Error, fallback: String) -> String {
        if let tinodeError = error as? TinodeError, case .notConnected(_) = tinodeError {
            return NSLocalizedString("暂时无法连接服务器，请检查网络后重试", comment: "Server unavailable")
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("ssl") || message.contains("certificate") || message.contains("handshake") {
            return NSLocalizedString("安全连接失败，请检查网络或服务器证书", comment: "Secure connection failure")
        }
        if message.contains("timed out") || message.contains("timeout") {
            return NSLocalizedString("连接超时，请检查网络后重试", comment: "Connection timeout")
        }
        if message.contains("not connected") || message.contains("unable to resolve") ||
            message.contains("network is unreachable") || message.contains("connection refused") ||
            message.contains("failed to connect") {
            return NSLocalizedString("暂时无法连接服务器，请检查网络后重试", comment: "Server unavailable")
        }
        return fallback
    }
}

enum ClawAuthFormValidation {
    enum Result: Equatable {
        case ok
        case accountRequired
        case accountInvalid
        case passwordRequired
        case passwordPolicy
        case inviteRequired
        case passwordMismatch
    }

    static func validateLogin(accountName: String, password: String) -> Result {
        if accountName.isEmpty { return .accountRequired }
        if !ClawAuthInput.isAccountNameValid(accountName) { return .accountInvalid }
        if password.isEmpty { return .passwordRequired }
        return .ok
    }

    static func validateSignUp(accountName: String, password: String, inviteCode: String) -> Result {
        let loginResult = validateLogin(accountName: accountName, password: password)
        if loginResult != .ok { return loginResult }
        if !ClawAuthInput.isPasswordValid(password) { return .passwordPolicy }
        if inviteCode.isEmpty { return .inviteRequired }
        return .ok
    }

    static func validatePasswordChange(password: String, confirmation: String) -> Result {
        if password.isEmpty { return .passwordRequired }
        if !ClawAuthInput.isPasswordValid(password) { return .passwordPolicy }
        if password != confirmation { return .passwordMismatch }
        return .ok
    }
}

final class ClawSubmissionGate {
    private let lock = NSLock()
    private var submitting = false

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !submitting else { return false }
        submitting = true
        return true
    }

    func finish() {
        lock.lock()
        submitting = false
        lock.unlock()
    }

    var isSubmitting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return submitting
    }
}

/// D1 profile rows share the same labels, spacing and adaptive table-header sizing.
enum ClawProfileLayout {
    static func label(_ text: String, size: CGFloat = 13, color: UIColor = ClawTheme.muted) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = ClawTheme.font(size)
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func valueRow(title: String, value: UILabel) -> UIStackView {
        let caption = label(title, size: 16, color: ClawTheme.ink)
        caption.setContentHuggingPriority(.required, for: .horizontal)
        value.font = ClawTheme.font(13)
        value.textColor = ClawTheme.muted
        value.numberOfLines = 0
        value.adjustsFontForContentSizeCategory = true
        value.textAlignment = .right
        let row = UIStackView(arrangedSubviews: [caption, value])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        row.backgroundColor = ClawTheme.surface
        row.layer.cornerRadius = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return row
    }

    static func fitHeader(in table: UITableView) {
        guard let header = table.tableHeaderView, table.bounds.width > 0 else { return }
        let height = ceil(header.systemLayoutSizeFitting(
            CGSize(width: table.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
        if abs(header.frame.width - table.bounds.width) > 0.5 || abs(header.frame.height - height) > 0.5 {
            header.frame = CGRect(x: 0, y: 0, width: table.bounds.width, height: height)
            table.tableHeaderView = header
        }
    }
}

enum AccountNames {
    static let basicTagPrefix = "basic:"

    static func normalize(_ value: String?) -> String {
        return (value ?? "").lowercased()
    }

    static func fromTags(_ tags: [String]?) -> String? {
        return UserDb.publicAccountName(from: tags)
    }

    static func fromBasicTag(_ tag: String?) -> String? {
        guard let tag = tag,
              tag.lowercased().hasPrefix(basicTagPrefix) else { return nil }
        return UserDb.publicAccountName(from: [tag])
    }

    static func matchesPublicSearchName(tags: [String]?, query: String?) -> Bool {
        let normalized = normalize(query)
        guard !normalized.isEmpty, !isUserIdLike(normalized), let tags = tags else {
            return false
        }
        let expectedBasic = basicTagPrefix + normalized
        let expectedAlias = Tinode.kTagAlias + normalized
        return tags.contains { tag in
            let normalizedTag = normalize(tag)
            return normalized == normalizedTag ||
                expectedBasic == normalizedTag ||
                expectedAlias == normalizedTag
        }
    }

    static func exactLookupQuery(_ accountName: String) -> String {
        return basicTagPrefix + normalize(accountName)
    }

    static func directorySearchQuery(_ query: String) -> String? {
        let normalized = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty, !isUserIdLike(normalized) else { return nil }
        if ClawAuthInput.isAccountNameValid(normalized) {
            return "\(exactLookupQuery(normalized)),\(Tinode.kTagAlias)\(query),\(query)"
        }
        return "\(Tinode.kTagAlias)\(query),\(query)"
    }

    static func isUserIdLike(_ value: String?) -> Bool {
        let normalized = normalize(value)
        return normalized.hasPrefix("usr") && normalized.count > 8
    }

    static func contactListSecondary(accountName: String?) -> String? {
        let normalized = normalize(accountName)
        return isPublicAccountName(normalized) ? normalized : nil
    }

    static func contactDisplayName(displayName: String?, accountName: String?, userId: String?, genericDefaultName: String = "CLAW OS") -> String {
        let normalizedDisplayName = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedDisplayName.isEmpty && !isGeneratedIdDisplayName(normalizedDisplayName, userId: userId) {
            return normalizedDisplayName
        }
        let normalizedAccountName = normalize(accountName)
        if isPublicAccountName(normalizedAccountName) {
            return normalizedAccountName
        }
        let fallback = genericDefaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "CLAW OS" : fallback
    }

    private static func isGeneratedIdDisplayName(_ displayName: String, userId: String?) -> Bool {
        guard let userId = userId, !userId.isEmpty else { return false }
        return displayName == "CLAW OS用户\(userId)" ||
            displayName == "CLAW OS用户 \(userId)" ||
            displayName.lowercased() == "claw os user \(userId)".lowercased()
    }

    private static func isPublicAccountName(_ value: String?) -> Bool {
        guard let value = value, !value.isEmpty else { return false }
        return UserDb.publicAccountName(from: [Tinode.kTagAlias + value, basicTagPrefix + value]) != nil
    }
}

/// Immutable, UI-ready representation of an incoming message notice.
///
/// Keep normalization and de-duplication inputs in one place so socket and
/// push notifications produce the same preview and delivery key on iOS.
struct ClawMessageNotice: Equatable {
    static let maxBodyLength = 120

    let topic: String
    let title: String
    let body: String
    let seq: Int

    init(topic: String?, title: String?, body: String?, seq: Int? = nil) {
        self.topic = Self.clean(topic)
        self.title = Self.clean(title)
        self.body = Self.shorten(Self.clean(body))
        self.seq = max(0, seq ?? 0)
    }

    var canOpenTopic: Bool {
        return !topic.isEmpty
    }

    var deliveryKey: String {
        return "\(topic):\(seq)"
    }

    private static func clean(_ value: String?) -> String {
        guard let value = value else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func shorten(_ value: String) -> String {
        guard value.count > maxBodyLength else { return value }
        let end = value.index(value.startIndex, offsetBy: maxBodyLength - 1)
        return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}


// AUTH-A1 UIKit/SDK bridge. The Foundation flow owns no global account state.
final class ClawIdentityCoordinator {
    let owner: Tinode
    let flow: ClawIdentityFlow
    private let current: () -> Bool
    private let origin: URL

    init(purpose: ClawIdentityPurpose) throws {
        let owner = Cache.tinode
        let connection = Tinode.getConnectionParams()
        guard let apiKey = Cache.ifCurrent(owner, { owner.apiKey }),
              let origin = URL(string: (connection.1 ? "https://" : "http://") + connection.0 + "/") else {
            throw ClawIdentityError.unavailable
        }
        self.owner = owner
        self.origin = origin
        let service = try ClawIdentityService(origin: origin, apiKey: apiKey)
        let current: () -> Bool = {
            let configured = Tinode.getConnectionParams()
            return configured.0 == connection.0 && configured.1 == connection.1 && Cache.isCurrent(owner)
        }
        self.current = current
        flow = ClawIdentityFlow(purpose: purpose, service: service, snapshotIsCurrent: current,
            loginBridge: { http, completed in
                guard current() else { completed(.failure(.ended)); return }
                do {
                    guard let connected = try owner.connectDefault(inBackground: false) else {
                        completed(.failure(.unavailable)); return
                    }
                    connected.thenApply { _ in
                        guard current(), owner.hostURL(useWebsocketProtocol: false) == origin else {
                            throw ClawIdentityError.ended
                        }
                        return owner.loginToken(token: http.token, creds: nil)
                    }.then(onSuccess: { response in
                        guard current(), let code = response?.ctrl?.code, (200..<300).contains(code),
                              owner.isConnectionAuthenticated, let uid = owner.myUid,
                              let token = owner.authToken else {
                            completed(.failure(.invalidResponse)); return nil
                        }
                        completed(.success(ClawIdentitySessionResult(user: uid, token: token,
                                                                    expires: owner.authTokenExpires)))
                        return nil
                    }, onFailure: { _ in
                        completed(.failure(.unavailable))
                        return nil
                    })
                } catch {
                    completed(.failure(.unavailable))
                }
            },
            retireSession: { Cache.invalidate(ifCurrent: owner) },
            commitSession: { session in
                Cache.ifCurrent(owner) {
                    guard current(), owner.myUid == session.user, owner.isConnectionAuthenticated else { return false }
                    SharedUtils.saveAuthToken(for: session.user, token: session.token, expires: session.expires)
                    owner.setAutoLoginWithToken(token: session.token)
                    return true
                } ?? false
            })
    }


    func loginLegacy(username: String, password: String,
                     completion: @escaping (Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void) {
        let owner = owner
        let current = current
        let origin = origin
        flow.loginLegacy(username: username, password: password, bridge: { username, password, completed in
            do {
                guard current(), let connected = try owner.connectDefault(inBackground: false) else {
                    completed(.failure(.ended)); return
                }
                connected.thenApply { _ in
                    guard current(), owner.hostURL(useWebsocketProtocol: false) == origin else {
                        throw ClawIdentityError.ended
                    }
                    return owner.loginBasic(uname: username, password: password)
                }.then(onSuccess: { response in
                    guard current(), let code = response?.ctrl?.code else {
                        completed(.failure(.ended)); return nil
                    }
                    guard (200..<300).contains(code) else {
                        completed(.failure(.legacyRecovery)); return nil
                    }
                    guard owner.isConnectionAuthenticated, let uid = owner.myUid, let token = owner.authToken else {
                        completed(.failure(.invalidResponse)); return nil
                    }
                    completed(.success(ClawIdentitySessionResult(user: uid, token: token, expires: owner.authTokenExpires)))
                    return nil
                }, onFailure: { _ in
                    completed(.failure(.server(code: "auth_invalid", retryAfter: nil)))
                    return nil
                })
            } catch { completed(.failure(.unavailable)) }
        }, completion: completion)
    }

    deinit { flow.invalidate() }
}

struct ClawIdentityLegalResources {
    let terms: URL?
    let privacy: URL?
    var available: Bool { terms != nil && privacy != nil }

    // Absent by default. Populate only through reviewed deployment configuration;
    // no legacy domain or fabricated policy is used as a fallback.
    static var configured: ClawIdentityLegalResources {
        func approvedURL(_ key: String) -> URL? {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  let url = URL(string: value), url.scheme == "https",
                  url.host != nil, url.user == nil, url.password == nil else { return nil }
            return url
        }
        return ClawIdentityLegalResources(terms: approvedURL("CLAWTermsURL"),
                                          privacy: approvedURL("CLAWPrivacyURL"))
    }
}

// Shared form primitives keep the three identity steps readable without changing storyboard routes.
final class ClawIdentityForm: UIView {
    let stack = UIStackView()
    let status = UILabel()
    private var keyboardObservers: [NSObjectProtocol] = []

    init(title: String, detail: String) {
        super.init(frame: .zero)
        backgroundColor = ClawTheme.background
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -32)
        ])
        let heading = label(title, size: 28, weight: .semibold)
        heading.accessibilityTraits = .header
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(label(detail, size: 16))
        status.font = ClawTheme.font(13, style: .footnote)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textColor = ClawTheme.muted
        status.accessibilityTraits = .updatesFrequently
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    func label(_ text: String, size: CGFloat = 13, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = ClawTheme.font(size, weight: weight)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = size >= 20 ? ClawTheme.ink : ClawTheme.muted
        return label
    }
    func field(_ title: String, secure: Bool = false) -> UITextField {
        stack.addArrangedSubview(label(title))
        let field = UITextField()
        field.placeholder = title
        field.accessibilityLabel = title
        field.font = ClawTheme.font(16)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.isSecureTextEntry = secure
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        ClawTheme.styleTextField(field)
        if secure { field.textContentType = .newPassword; field.showSecureEntrySwitch() }
        stack.addArrangedSubview(field)
        return field
    }
    func button(_ title: String, target: Any, action: Selector, primary: Bool = true) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        if primary { ClawTheme.stylePrimaryButton(button) } else { ClawTheme.styleSecondaryButton(button) }
        button.addTarget(target, action: action, for: .touchUpInside)
        stack.addArrangedSubview(button)
        return button
    }
    func finish() { stack.addArrangedSubview(status) }
    func setField(_ field: UITextField, visible: Bool) {
        field.isHidden = !visible
        if let index = stack.arrangedSubviews.firstIndex(of: field), index > 0 {
            stack.arrangedSubviews[index - 1].isHidden = !visible
        }
    }
    func fit(in table: UITableView) {
        let width = table.bounds.width
        guard width > 0 else { return }
        let height = ceil(systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
        if table.tableHeaderView !== self || abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 {
            frame = CGRect(x: 0, y: 0, width: width, height: height)
            table.tableHeaderView = self
        }
    }
    func install(in controller: UIViewController) {
        controller.view.subviews.forEach { $0.isHidden = true }
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        scroll.backgroundColor = ClawTheme.background
        controller.view.addSubview(scroll)
        translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(self)
        let bottom: NSLayoutYAxisAnchor
        if #available(iOS 15.0, *) {
            bottom = controller.view.keyboardLayoutGuide.topAnchor
        } else {
            bottom = controller.view.safeAreaLayoutGuide.bottomAnchor
            for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
                keyboardObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak scroll] note in
                    guard let scroll = scroll, scroll.window != nil else { return }
                    let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                    let inset = note.name == UIResponder.keyboardWillHideNotification ? 0
                        : max(0, scroll.bounds.maxY - scroll.convert(frame, from: nil).minY)
                    scroll.contentInset.bottom = inset
                    scroll.verticalScrollIndicatorInsets.bottom = inset
                })
            }
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottom),
            leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }
}


class ClawIdentityEntryController: UITableViewController {
    var identityPurpose: ClawIdentityPurpose { .register }
    private var coordinator: ClawIdentityCoordinator?
    private var form: ClawIdentityForm!
    private let methodPicker = UISegmentedControl(items: ["手机号", "邮箱"])
    private var country: UITextField!
    private var identifier: UITextField!
    private var submit: UIButton!
    private var consent: UIButton?
    private var termsAccepted = false
    private let legal = ClawIdentityLegalResources.configured
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = identityPurpose == .register ? "创建账号" : "找回密码"
        form = ClawIdentityForm(title: title ?? "", detail: identityPurpose == .register
            ? "先验证手机号或邮箱，再设置密码。" : "验证已绑定的手机号或邮箱后，重新设置密码。")
        tableView.backgroundColor = ClawTheme.background
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        methodPicker.selectedSegmentIndex = 0
        methodPicker.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        methodPicker.addTarget(self, action: #selector(methodChanged), for: .valueChanged)
        form.stack.addArrangedSubview(methodPicker)
        country = form.field("国家码")
        country.text = "+86"
        country.keyboardType = .phonePad
        identifier = form.field("手机号")
        identifier.textContentType = .telephoneNumber
        identifier.keyboardType = .phonePad
        if identityPurpose == .register {
            consent = form.button("我已阅读并同意服务条款和隐私政策", target: self, action: #selector(toggleConsent), primary: false)
            consent?.setImage(ClawTheme.symbol("square", pointSize: 20), for: .normal)
            _ = form.button(legal.terms == nil ? "服务条款未配置" : "查看服务条款",
                            target: self, action: #selector(openTerms), primary: false)
            _ = form.button(legal.privacy == nil ? "隐私政策未配置" : "查看隐私政策",
                            target: self, action: #selector(openPrivacy), primary: false)
        }
        submit = form.button("获取验证码", target: self, action: #selector(requestCodeFromForm))
        submit.accessibilityIdentifier = "claw.identity.challenge"
        _ = form.button("重新开始", target: self, action: #selector(restartIdentity), primary: false)
        form.finish()
        form.fit(in: tableView)
        UiUtils.dismissKeyboardForTaps(onView: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if coordinator?.flow.isCurrent != true { prepareIdentity() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshControls() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            coordinator?.flow.invalidate()
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); form?.fit(in: tableView) }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { .leastNonzeroMagnitude }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { .leastNonzeroMagnitude }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { .leastNonzeroMagnitude }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        cell.accessibilityElementsHidden = true
        return cell
    }
    deinit { timer?.invalidate() }

    private var selectedMethod: ClawIdentityMethod { methodPicker.selectedSegmentIndex == 0 ? .tel : .email }

    private func prepareIdentity() {
        submit.isEnabled = false
        form.status.text = "正在检查身份服务…"
        do {
            let coordinator = try ClawIdentityCoordinator(purpose: identityPurpose)
            self.coordinator = coordinator
            coordinator.flow.prepare { [weak self, weak coordinator] result in
                guard let self = self, let coordinator = coordinator, self.coordinator === coordinator else { return }
                switch result {
                case let .success(capabilities):
                    self.methodPicker.setEnabled(capabilities.methods.tel, forSegmentAt: 0)
                    self.methodPicker.setEnabled(capabilities.methods.email, forSegmentAt: 1)
                    if !capabilities.canDeliver(self.selectedMethod) {
                        self.methodPicker.selectedSegmentIndex = capabilities.methods.email ? 1 : 0
                    }
                    self.methodChanged()
                    self.form.status.text = capabilities.test_mode
                        ? "测试环境：验证码提交不代表真实短信或邮件投递。"
                        : "验证码提交后仍需等待短信或邮件到达。"
                    if !capabilities.methods.tel && !capabilities.methods.email {
                        self.form.status.text = "验证码服务暂不可用，请稍后再试。"
                    }
                    if self.identityPurpose == .register && !self.legal.available {
                        self.form.status.text = "服务条款和隐私政策尚未配置，当前暂不可注册。"
                    }
                case let .failure(error): self.form.status.text = error.message
                }
                self.refreshControls()
            }
        } catch { form.status.text = ClawIdentityError.unavailable.message }
    }

    @objc private func methodChanged() {
        let phone = selectedMethod == .tel
        form.setField(country, visible: phone)
        identifier.placeholder = phone ? "手机号" : "邮箱"
        identifier.accessibilityLabel = phone ? "手机号" : "邮箱"
        identifier.keyboardType = phone ? .phonePad : .emailAddress
        identifier.textContentType = phone ? .telephoneNumber : .emailAddress
        if let index = form.stack.arrangedSubviews.firstIndex(of: identifier), index > 0 {
            (form.stack.arrangedSubviews[index - 1] as? UILabel)?.text = phone ? "手机号" : "邮箱"
        }
        refreshControls()
        view.setNeedsLayout()
    }

    @objc private func toggleConsent() {
        guard legal.available else { form.status.text = "服务条款和隐私政策尚未配置，当前暂不可注册。"; return }
        termsAccepted.toggle()
        consent?.setImage(ClawTheme.symbol(termsAccepted ? "checkmark.square.fill" : "square", pointSize: 20), for: .normal)
        consent?.accessibilityValue = termsAccepted ? "已勾选" : "未勾选"
        refreshControls()
    }
    @objc private func openTerms() { openLegal(legal.terms) }
    @objc private func openPrivacy() { openLegal(legal.privacy) }
    private func openLegal(_ url: URL?) {
        guard let url = url else { form.status.text = "尚未提供已核实的法律资源，当前无法查看。"; return }
        UIApplication.shared.open(url)
    }
    @objc private func restartIdentity() {
        coordinator?.flow.invalidate()
        coordinator = nil
        termsAccepted = false
        consent?.setImage(ClawTheme.symbol("square", pointSize: 20), for: .normal)
        prepareIdentity()
    }

    private func refreshControls() {
        guard let flow = coordinator?.flow else { submit?.isEnabled = false; return }
        let pending = flow.pendingChallenge != nil
        let legalOK = identityPurpose != .register || (legal.available && termsAccepted)
        submit.isEnabled = flow.isCurrent && !flow.busy && legalOK
            && flow.capabilities?.canDeliver(selectedMethod) == true && (pending || flow.retrySeconds == 0)
        submit.setTitle(flow.busy ? "正在提交…" : pending ? "重试确认请求" :
            flow.retrySeconds > 0 ? "\(flow.retrySeconds) 秒后重新获取" : "获取验证码", for: .normal)
        methodPicker.isEnabled = !flow.busy && !pending
        identifier.isEnabled = !flow.busy && !pending
        country.isEnabled = !flow.busy && !pending
        consent?.isEnabled = !flow.busy && legal.available
    }

    @objc func requestCodeFromForm() {
        guard let coordinator = coordinator else { prepareIdentity(); return }
        coordinator.flow.requestCode(method: selectedMethod, input: identifier.text ?? "",
            countryCode: country.text ?? "+86", legalResourcesAvailable: legal.available, termsAccepted: termsAccepted) { [weak self, weak coordinator] result in
                guard let self = self, let coordinator = coordinator, self.coordinator === coordinator else { return }
                switch result {
                case .success:
                    let next = CredentialsViewController()
                    next.identityCoordinator = coordinator
                    next.identityLegalAccepted = self.termsAccepted && self.legal.available
                    self.navigationController?.pushViewController(next, animated: true)
                case let .failure(error): self.form.status.text = error.message
                }
                self.refreshControls()
            }
        refreshControls()
    }
}

final class ClawSetIdentityPasswordViewController: UIViewController {
    let coordinator: ClawIdentityCoordinator
    private var form: ClawIdentityForm!
    private var password: UITextField!
    private var confirmation: UITextField!
    private var submit: UIButton!
    private var reverify: UIButton!
    private var timer: Timer?

    init(coordinator: ClawIdentityCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = coordinator.flow.purpose == .register ? "设置密码" : "重置密码"
        view.backgroundColor = ClawTheme.background
        form = ClawIdentityForm(title: title ?? "", detail: "12–64 位英文字母、数字或符号，不含空格。请妥善保存密码。")
        password = form.field("新密码", secure: true)
        confirmation = form.field("再次输入新密码", secure: true)
        submit = form.button("确认设置", target: self, action: #selector(savePassword))
        reverify = form.button("重新验证身份", target: self, action: #selector(startAgain), primary: false)
        _ = form.button("返回登录", target: self, action: #selector(returnToLogin), primary: false)
        form.finish()
        form.install(in: self)
        UiUtils.dismissKeyboardForTaps(onView: view)
        refresh()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    deinit { timer?.invalidate() }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            password.text = nil
            confirmation.text = nil
            coordinator.flow.invalidate()
        }
    }
    private func refresh() {
        let flow = coordinator.flow
        let frozen = flow.pendingPassword != nil
        password.isEnabled = !flow.busy && !frozen && flow.registeredUser == nil
        confirmation.isEnabled = password.isEnabled
        let retry = flow.registeredUser == nil ? flow.mutationRetrySeconds : flow.loginRetrySeconds
        submit.isEnabled = flow.isCurrent && !flow.busy && retry == 0
            && (flow.canSetPassword || frozen || flow.registeredUser != nil)
        submit.setTitle(flow.busy ? "正在处理…" : retry > 0 ? "\(retry) 秒后重试" : flow.registeredUser != nil ? "继续登录" :
            frozen ? "重试确认结果" : "确认设置", for: .normal)
        reverify.isEnabled = !flow.busy
        if flow.isCurrent && !flow.busy && !flow.canSetPassword && !frozen && flow.registeredUser == nil {
            form.status.text = "身份验证已失效，请点击“重新验证身份”。"
        }
    }
    @objc private func savePassword() {
        let flow = coordinator.flow
        let value = password.text ?? ""
        guard value == confirmation.text else { form.status.text = "两次输入的密码不一致"; return }
        if flow.registeredUser != nil { loginRegistered(password: value); return }
        flow.setPassword(value) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(.registered):
                self.form.status.text = "账号已创建，正在登录…"
                self.loginRegistered(password: value)
            case .success(.reset):
                self.password.text = nil
                self.confirmation.text = nil
                self.coordinator.flow.invalidate()
                self.navigationController?.popToRootViewController(animated: true)
                UiUtils.showToast(message: "密码已重置，请重新登录")
            case let .failure(error):
                self.form.status.text = error.message
                if flow.pendingPassword != nil {
                    self.form.status.text = "提交结果未确认。请保持内容不变，点击“重试确认结果”。"
                }
            }
            self.refresh()
        }
        refresh()
    }
    private func loginRegistered(password: String) {
        let flow = coordinator.flow
        guard let method = flow.method, let value = flow.value else { startAgain(); return }
        flow.login(method: method, input: value, password: password) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.password.text = nil
                self.confirmation.text = nil
                UiUtils.routeToChatListVC(for: self.coordinator.owner)
            case let .failure(error):
                self.form.status.text = "注册已完成，暂时无法登录。\(error.message)；也可返回登录页重新登录。"
            }
            self.refresh()
        }
        refresh()
    }
    @objc private func returnToLogin() {
        password.text = nil
        confirmation.text = nil
        coordinator.flow.invalidate()
        navigationController?.popToRootViewController(animated: true)
    }
    @objc private func startAgain() {
        password.text = nil
        confirmation.text = nil
        coordinator.flow.invalidate()
        if let entry = navigationController?.viewControllers.first(where: { $0 is ClawIdentityEntryController }) {
            navigationController?.popToViewController(entry, animated: true)
        } else { navigationController?.popToRootViewController(animated: true) }
    }
}
