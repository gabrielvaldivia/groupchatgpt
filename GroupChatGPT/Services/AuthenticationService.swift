import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI

@MainActor
public class AuthenticationService: NSObject, ObservableObject {
    public static let shared = AuthenticationService()
    private let db = Firestore.firestore()

    @Published public var currentUser: User?
    @Published public var isAuthenticated = false
    @Published public var error: Error?

    private var signInContinuation: CheckedContinuation<Void, Error>?

    private override init() {
        super.init()
    }

    public func handleSignInWithAppleRequest() async throws {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }
    }

    public func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationService: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credentials = authorization.credential as? ASAuthorizationAppleIDCredential else {
            signInContinuation?.resume(
                throwing: NSError(
                    domain: "", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"]
                )
            )
            signInContinuation = nil
            return
        }

        let userId = credentials.user
        let name = [credentials.fullName?.givenName, credentials.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        let user = User(
            id: userId,
            name: name.isEmpty ? "User" : name,
            email: credentials.email
        )

        // Save to Firestore
        do {
            try db.collection("users").document(userId).setData(from: user)
            self.currentUser = user
            self.isAuthenticated = true
            signInContinuation?.resume()
        } catch {
            signInContinuation?.resume(throwing: error)
        }
        signInContinuation = nil
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        self.error = error
        signInContinuation?.resume(throwing: error)
        signInContinuation = nil
    }
}
