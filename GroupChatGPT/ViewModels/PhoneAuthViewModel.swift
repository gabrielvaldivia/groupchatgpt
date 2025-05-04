import Combine
import FirebaseAuth
import Foundation

@MainActor
class PhoneAuthViewModel: ObservableObject {
    @Published var phoneNumber: String = ""
    @Published var verificationCode: String = ""
    @Published var verificationID: String?
    @Published var isCodeSent: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var isAuthenticated: Bool = false

    func sendCode() {
        self.error = nil
        self.isLoading = true
        print("[PhoneAuthViewModel] Attempting to send code to: \(phoneNumber)")
        PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) {
            verificationID, error in
            print("[PhoneAuthViewModel] verifyPhoneNumber callback fired")
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    print("[PhoneAuthViewModel] Error from verifyPhoneNumber: \(error)")
                    self.error = error.localizedDescription
                } else {
                    print(
                        "[PhoneAuthViewModel] VerificationID received: \(String(describing: verificationID))"
                    )
                    self.verificationID = verificationID
                    self.isCodeSent = true
                }
            }
        }
        print("[PhoneAuthViewModel] verifyPhoneNumber called")
    }

    func verifyCode() {
        guard let verificationID = verificationID else { return }
        self.error = nil
        self.isLoading = true
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        Auth.auth().signIn(with: credential) { result, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.error = error.localizedDescription
                } else {
                    self.isAuthenticated = true
                }
            }
        }
    }
}
