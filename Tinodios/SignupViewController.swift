import UIKit
import PhoneNumberKit

// Keep existing storyboard connections; registration now starts with AUTH-A1 verification.
class SignupViewController: ClawIdentityEntryController {
    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var loginTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var telTextField: PhoneNumberTextField!
    @IBOutlet weak var signUpButton: UIButton!

    @IBAction func signUpClicked(_ sender: Any) { requestCodeFromForm() }
    @IBAction func addAvatarClicked(_ sender: Any) {
        // Profile editing is available after successful login; no anonymous media upload.
    }
}
