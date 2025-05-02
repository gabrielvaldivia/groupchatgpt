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
    private var isSigningIn = false
    private var userListener: ListenerRegistration?
    private var authStateListener: AuthStateDidChangeListenerHandle?

    private override init() {
        super.init()
        setupUserListener()
    }

    private func setupUserListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }

            if let userId = user?.uid {
                self.userListener?.remove()
                self.userListener = self.db.collection("users").document(userId)
                    .addSnapshotListener { [weak self] snapshot, error in
                        guard let self = self else { return }

                        if let error = error {
                            self.error = error
                            return
                        }

                        if let snapshot = snapshot, snapshot.exists {
                            do {
                                let user = try snapshot.data(as: User.self)
                                self.currentUser = user
                                self.isAuthenticated = true
                            } catch {
                                self.error = error
                            }
                        } else {
                            self.currentUser = nil
                            self.isAuthenticated = false
                        }
                    }
            } else {
                self.userListener?.remove()
                self.userListener = nil
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }

    public func handleSignInWithAppleRequest() async throws {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }

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
            userListener?.remove()
            userListener = nil
            currentUser = nil
            isAuthenticated = false
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }

    deinit {
        userListener?.remove()
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
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If no name is provided during sign in, use "New User" and prompt them to update in profile
        let displayName = name.isEmpty ? "New User" : name

        let user = User(
            id: userId,
            name: displayName,
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
