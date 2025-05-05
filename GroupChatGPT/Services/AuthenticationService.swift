import AuthenticationServices
import CryptoKit
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
    private var currentNonce: String?

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

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError(
                        "Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)"
                    )
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }

    public func handleSignInWithAppleRequest() async throws {
        print("[AuthenticationService] handleSignInWithAppleRequest called")
        guard !isSigningIn else {
            print("[AuthenticationService] Already signing in, ignoring duplicate request")
            return
        }
        isSigningIn = true
        defer {
            print("[AuthenticationService] Sign in process completed")
            isSigningIn = false
            currentNonce = nil
        }

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let rawNonce = randomNonceString()
        currentNonce = rawNonce
        request.nonce = sha256(rawNonce)

        print("[AuthenticationService] Created authorization request")
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        print("[AuthenticationService] Starting authorization request")
        return try await withCheckedThrowingContinuation { continuation in
            print("[AuthenticationService] Setting up continuation")
            self.signInContinuation = continuation
            print("[AuthenticationService] Performing authorization request")
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
        print("[AuthenticationService] Authorization completed successfully")
        guard let credentials = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("[AuthenticationService] Invalid credentials received")
            let error = NSError(
                domain: "", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"]
            )
            signInContinuation?.resume(throwing: error)
            signInContinuation = nil
            return
        }

        print("[AuthenticationService] Processing Apple ID credentials")
        let userId = credentials.user
        let firstName = credentials.fullName?.givenName ?? "New User"
        let email = credentials.email

        // Create Firebase credential
        guard let identityToken = credentials.identityToken,
            let tokenString = String(data: identityToken, encoding: .utf8),
            let nonce = currentNonce
        else {
            print("[AuthenticationService] Failed to get identity token or nonce")
            let error = NSError(
                domain: "", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get identity token or nonce"]
            )
            signInContinuation?.resume(throwing: error)
            signInContinuation = nil
            return
        }

        let firebaseCredential = OAuthProvider.credential(
            withProviderID: "apple.com",
            idToken: tokenString,
            rawNonce: nonce
        )

        print("[AuthenticationService] Signing in with Firebase")
        Auth.auth().signIn(with: firebaseCredential) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print(
                    "[AuthenticationService] Firebase sign in failed: \(error.localizedDescription)"
                )
                self.signInContinuation?.resume(throwing: error)
                self.signInContinuation = nil
                return
            }

            guard let userId = result?.user.uid else {
                print("[AuthenticationService] No user ID received from Firebase")
                let error = NSError(
                    domain: "", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No user ID received"]
                )
                self.signInContinuation?.resume(throwing: error)
                self.signInContinuation = nil
                return
            }

            // Check if user already exists in Firestore
            self.db.collection("users").document(userId).getDocument {
                [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print(
                        "[AuthenticationService] Error checking existing user: \(error.localizedDescription)"
                    )
                    self.signInContinuation?.resume(throwing: error)
                    self.signInContinuation = nil
                    return
                }

                if let snapshot = snapshot, snapshot.exists {
                    // User exists, just update the last login date
                    print("[AuthenticationService] User already exists, updating last login date")
                    do {
                        let user = try snapshot.data(as: User.self)
                        self.currentUser = user
                        self.isAuthenticated = true

                        // Update last login date
                        try self.db.collection("users").document(userId).updateData([
                            "lastLoginDate": Timestamp(date: Date())
                        ])

                        self.signInContinuation?.resume()
                    } catch {
                        print(
                            "[AuthenticationService] Error updating user: \(error.localizedDescription)"
                        )
                        self.signInContinuation?.resume(throwing: error)
                    }
                } else {
                    // Create new user
                    print("[AuthenticationService] Creating new user with ID: \(userId)")
                    let user = User(
                        id: userId,
                        name: firstName,
                        email: email
                    )

                    print("[AuthenticationService] Attempting to save user to Firestore")
                    do {
                        try self.db.collection("users").document(userId).setData(from: user)
                        print("[AuthenticationService] User saved successfully")
                        self.currentUser = user
                        self.isAuthenticated = true
                        self.signInContinuation?.resume()
                    } catch {
                        print(
                            "[AuthenticationService] Error saving user: \(error.localizedDescription)"
                        )
                        self.signInContinuation?.resume(throwing: error)
                    }
                }
                self.signInContinuation = nil
            }
        }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        print(
            "[AuthenticationService] Authorization failed with error: \(error.localizedDescription)"
        )
        self.error = error
        signInContinuation?.resume(throwing: error)
        signInContinuation = nil
    }
}
