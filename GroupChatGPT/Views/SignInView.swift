import AuthenticationServices
import FirebaseAuth
import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.colorScheme) var colorScheme
    @State private var showError = false
    @State private var isSigningIn = false
    @State private var hasRequestedSignIn = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Hola")
                .font(.largeTitle)
                .bold()

            Text("Sign in to start chatting")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            SignInWithAppleButton(
                onRequest: { request in
                    print("[SignInView] Apple Sign In requested")
                    guard !hasRequestedSignIn else {
                        print("[SignInView] Sign in already requested, ignoring")
                        return
                    }
                    hasRequestedSignIn = true
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    print("[SignInView] Apple Sign In completion handler called")
                    guard !isSigningIn else {
                        print("[SignInView] Already signing in, ignoring duplicate request")
                        return
                    }
                    isSigningIn = true

                    Task {
                        do {
                            print("[SignInView] Starting sign in process")
                            try await authService.handleSignInWithAppleRequest()
                            print("[SignInView] Sign in completed successfully")
                        } catch {
                            print("[SignInView] Sign in failed: \(error.localizedDescription)")
                            showError = true
                            hasRequestedSignIn = false
                        }
                        isSigningIn = false
                    }
                }
            )
            .signInWithAppleButtonStyle(
                colorScheme == .dark ? .white : .black
            )
            .frame(height: 45)
            .padding(.horizontal, 40)
            .disabled(isSigningIn)

            Spacer()
        }
        .padding()
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {
                hasRequestedSignIn = false
            }
        } message: {
            Text("Please try again.")
        }
    }
}
