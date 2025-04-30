import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct UserListView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showingProfile = false

    var body: some View {
        Group {
            if users.isEmpty && !isLoading {
                VStack(spacing: 16) {
                    Text("No Users Found")
                        .font(.headline)
                    Text("There are no other users to chat with yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Refresh") {
                        loadUsers()
                    }
                }
            } else {
                userList
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingProfile = true
                } label: {
                    Image(systemName: "person.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                signOutButton
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(authService)
        }
        .overlay {
            if isLoading {
                loadingOverlay
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
        .refreshable {
            await refreshUsers()
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

        Task {
            await refreshUsers()
        }
    }

    private func refreshUsers() async {
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("users").getDocuments()

            let fetchedUsers = snapshot.documents.compactMap { document -> User? in
                do {
                    return try document.data(as: User.self)
                } catch {
                    print("Error decoding user document: \(error)")
                    return nil
                }
            }

            await MainActor.run {
                self.users = fetchedUsers
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
            }
        }
    }
}

struct UserRow: View {
    let user: User
    @State private var uiImage: UIImage?

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
                if url.absoluteString.hasPrefix("data:") {
                    if let image = loadBase64Image(from: url.absoluteString) {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        defaultAvatar
                    }
                } else {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        defaultAvatar
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
            } else {
                defaultAvatar
            }
        }
    }

    private func loadBase64Image(from dataURL: String) -> Image? {
        guard let base64String = dataURL.components(separatedBy: ",").last,
            let imageData = Data(base64Encoded: base64String),
            let uiImage = UIImage(data: imageData)
        else {
            return nil
        }
        return Image(uiImage: uiImage)
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
