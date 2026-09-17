import UIKit
import PhoneNumberKit

class ResetPasswordViewController: ClawIdentityEntryController {
    override var identityPurpose: ClawIdentityPurpose { .reset }
    @IBOutlet weak var promptLabel: UILabel!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var telTextField: PhoneNumberTextField!
    @IBOutlet weak var confirmationCodeTextField: UITextField!
    @IBOutlet weak var newPasswordTextField: UITextField!

    @IBAction func haveCodeClicked(_ sender: Any) { requestCodeFromForm() }
    @IBAction func requestCodeClicked(_ sender: Any) { requestCodeFromForm() }
    @IBAction func confirmCodeClicked(_ sender: Any) { requestCodeFromForm() }
}
