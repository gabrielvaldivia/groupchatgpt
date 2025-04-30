import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct UserListView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                userList

                if isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    signOutButton
                }
            }
        }
        .alert(
            "Error", isPresented: $showError,
            actions: {
                Button("OK") {
                    errorMessage = nil
                }
            },
            message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        )
        .onAppear {
            loadUsers()
        }
    }

    private var userList: some View {
        List {
            ForEach(users) { user in
                if user.id != authService.currentUser?.id {
                    NavigationLink {
                        ChatView(otherUser: user)
                    } label: {
                        UserRow(user: user)
                    }
                }
            }
        }
    }

    private var loadingOverlay: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.1))
    }

    private var signOutButton: some View {
        Button("Sign Out") {
            authService.signOut()
        }
    }

    private func loadUsers() {
        isLoading = true
        // TODO: Implement user fetching from your backend
        // For now, let's use some sample data
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            users = [
                User(id: "1", name: "Alice Smith"),
                User(id: "2", name: "Bob Johnson"),
                User(id: "3", name: "Carol Williams"),
            ]
            isLoading = false
        }
    }
}

struct UserRow: View {
    let user: User

    var body: some View {
        HStack {
            userAvatar
            userInfo
        }
        .padding(.vertical, 4)
    }

    private var userAvatar: some View {
        Group {
            if let url = user.profileImageURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    defaultAvatar
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                defaultAvatar
            }
        }
    }

    private var defaultAvatar: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 40, height: 40)
            .foregroundStyle(.gray)
    }

    private var userInfo: some View {
        VStack(alignment: .leading) {
            Text(user.name)
                .font(.headline)
        }
        .padding(.leading, 8)
    }
}
