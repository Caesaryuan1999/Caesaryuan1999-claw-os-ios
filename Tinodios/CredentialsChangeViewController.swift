import PhoneNumberKit
import TinodeSDK
import UIKit

// AUTH-A1 supports registration and recovery, not credential rebinding.
// Keep this storyboard destination read-only even if reached through an old route.
class CredentialsChangeViewController: UITableViewController {
    @IBOutlet weak var currentEmailField: UITextField!
    @IBOutlet weak var currentTelField: PhoneNumberTextField!
    @IBOutlet weak var newEmailField: UITextField!
    @IBOutlet weak var newTelField: PhoneNumberTextField!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var confirmationCodeField: UITextField!

    var currentCredential: Credential?
    var newCred: String?
    private var header: ClawIdentityForm!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登录方式"
        view.backgroundColor = ClawTheme.background
        ClawTheme.styleList(tableView, rowHeight: UITableView.automaticDimension)
        let fields: [UITextField?] = [currentEmailField, currentTelField, newEmailField, newTelField, confirmationCodeField]
        for field in fields {
            field?.isEnabled = false
            if let field = field { ClawTheme.styleTextField(field) }
        }
        currentEmailField.text = currentCredential?.meth == Credential.kMethEmail ? currentCredential?.val : nil
        currentTelField.text = currentCredential?.meth == Credential.kMethPhone ? currentCredential?.val : nil
        newEmailField.text = nil
        newTelField.text = nil
        confirmationCodeField.text = nil
        infoLabel.text = "更换手机号或邮箱暂未开放"
        header = ClawIdentityForm(title: "登录方式", detail: "更换手机号或邮箱暂未开放。现有登录方式继续保留，可用于登录或找回密码。")
        header.fit(in: tableView)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        header?.fit(in: tableView)
    }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.section == 0,
              (indexPath.row == 0 && currentCredential?.meth == Credential.kMethEmail)
                || (indexPath.row == 1 && currentCredential?.meth == Credential.kMethPhone) else {
            return .leastNonzeroMagnitude
        }
        return max(60, super.tableView(tableView, heightForRowAt: indexPath))
    }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { .leastNonzeroMagnitude }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { .leastNonzeroMagnitude }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.accessibilityElementsHidden = indexPath.section != 0
    }
    @IBAction func requestClicked(_ sender: Any) {
        UiUtils.showToast(message: "更换手机号或邮箱暂未开放")
    }
    @IBAction func confirmClicked(_ sender: Any) {
        UiUtils.showToast(message: "更换手机号或邮箱暂未开放")
    }
}
