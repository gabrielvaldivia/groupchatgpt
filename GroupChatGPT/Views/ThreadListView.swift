import FirebaseFirestore
import SwiftUI

struct ThreadListView: View {
    @StateObject private var viewModel = ThreadListViewModel()
    @State private var showingCreateThread = false
    @State private var showingProfile = false
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        ZStack {
            if viewModel.threads.isEmpty {
                VStack(spacing: 16) {
                    Text("No Threads")
                        .font(.headline)
                    Text("Create a new thread to start chatting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(viewModel.threads) { thread in
                        NavigationLink {
                            ChatView(thread: thread)
                                .environmentObject(authService)
                        } label: {
                            ThreadRow(thread: thread)
                                .environmentObject(viewModel)
                                .id(viewModel.lastReadTimestamps[thread.id ?? ""] ?? 0)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            if let index = indexSet.first {
                                try? await viewModel.deleteThread(viewModel.threads[index])
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Threads")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingProfile = true
                } label: {
                    if let user = authService.currentUser {
                        if let url = user.profileImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProfilePhotoView(
                                        image: nil, name: user.name, size: 32,
                                        placeholderColor: user.placeholderColor)
                                case .success(let image):
                                    ProfilePhotoView(
                                        image: image, name: user.name, size: 32,
                                        placeholderColor: user.placeholderColor)
                                case .failure(_):
                                    ProfilePhotoView(
                                        image: nil, name: user.name, size: 32,
                                        placeholderColor: user.placeholderColor)
                                @unknown default:
                                    ProfilePhotoView(
                                        image: nil, name: user.name, size: 32,
                                        placeholderColor: user.placeholderColor)
                                }
                            }
                        } else {
                            ProfilePhotoView(
                                image: nil, name: user.name, size: 32,
                                placeholderColor: user.placeholderColor)
                        }
                    } else {
                        Image(systemName: "person.circle")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateThread = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateThread) {
            CreateThreadView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(authService)
        }
    }
}

struct ThreadRow: View {
    let thread: Thread
    @State private var participantUsers: [String: User] = [:]
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var viewModel: ThreadListViewModel
    @State private var isUnread: Bool = false

    private func updateUnreadState() {
        isUnread = viewModel.isThreadUnread(thread)
        print("ThreadRow: Thread \(thread.id ?? "unknown") isUnread: \(isUnread)")
    }

    var body: some View {
        HStack {
            if isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.name)
                    .font(.headline)
                if let lastMessage = thread.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Facepile
            HStack(spacing: -8) {
                ForEach(thread.participants.prefix(3), id: \.self) { userId in
                    if let user = participantUsers[userId] {
                        if let url = user.profileImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 40, height: 40)
                                case .success(let image):
                                    ProfilePhotoView(
                                        image: image, name: user.name, size: 40,
                                        placeholderColor: user.placeholderColor
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                case .failure(_):
                                    ProfilePhotoView(
                                        image: nil, name: user.name, size: 40,
                                        placeholderColor: user.placeholderColor
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                @unknown default:
                                    ProfilePhotoView(
                                        image: nil, name: user.name, size: 40,
                                        placeholderColor: user.placeholderColor
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                }
                            }
                        } else {
                            ProfilePhotoView(
                                image: nil, name: user.name, size: 40,
                                placeholderColor: user.placeholderColor
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 2)
                            )
                        }
                    } else {
                        ProgressView()
                            .frame(width: 40, height: 40)
                    }
                }
                if thread.participants.count > 3 {
                    Text("+\(thread.participants.count - 3)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        )
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            updateUnreadState()
        }
        .onChange(of: thread) { _ in
            updateUnreadState()
        }
        .onChange(of: viewModel.lastReadTimestamps) { _ in
            updateUnreadState()
        }
        .task {
            await loadParticipantUsers()
        }
    }

    private func loadParticipantUsers() async {
        let db = Firestore.firestore()
        for userId in thread.participants {
            if participantUsers[userId] == nil {
                do {
                    let document = try await db.collection("users").document(userId).getDocument()
                    if let user = try? document.data(as: User.self) {
                        participantUsers[userId] = user
                    }
                } catch {
                    print("Error loading user \(userId): \(error.localizedDescription)")
                }
            }
        }
    }
}
