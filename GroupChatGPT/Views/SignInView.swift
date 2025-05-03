import AuthenticationServices
import FirebaseAuth
import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.colorScheme) var colorScheme
    @State private var showError = false
    @State private var isSigningIn = false

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
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    guard !isSigningIn else { return }
                    isSigningIn = true

                    Task {
                        do {
                            try await authService.handleSignInWithAppleRequest()
                        } catch {
                            print("Sign in failed: \(error.localizedDescription)")
                            showError = true
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
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }
}
