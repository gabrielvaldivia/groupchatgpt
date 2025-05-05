import SwiftUI

struct CreateThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateThreadViewModel()
    @State private var threadName = ""
    @State private var apiKey = ""
    @State private var showError = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ParticipantSelectionView(viewModel: viewModel)
                .navigationTitle("Select Participants")
                .navigationDestination(for: String.self) { _ in
                    ThreadDetailsView(
                        threadName: $threadName,
                        apiKey: $apiKey,
                        viewModel: viewModel,
                        dismiss: dismiss
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Next") {
                            path.append("details")
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .alert("Error", isPresented: $showError, presenting: viewModel.error) { _ in
                    Button("OK") {
                        viewModel.clearError()
                    }
                } message: { error in
                    if let error = error as? CreateThreadViewModel.CreateThreadError {
                        Text(error.localizedDescription)
                    } else {
                        Text(error.localizedDescription)
                    }
                }
        }
    }
}

struct ParticipantSelectionView: View {
    @ObservedObject var viewModel: CreateThreadViewModel

    var body: some View {
        if viewModel.isLoading {
            ProgressView("Loading users...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.availableUsers.isEmpty {
            ContentUnavailableView(
                "No Users Found",
                systemImage: "person.2.slash",
                description: Text("There are no other users available to chat with.")
            )
        } else {
            List {
                ForEach(viewModel.filteredUsers) { user in
                    Button(action: {
                        viewModel.toggleUser(user)
                    }) {
                        UserSelectionRow(user: user, isSelected: viewModel.isUserSelected(user))
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search")
            .overlay(alignment: .bottom) {
                if !viewModel.selectedUsers.isEmpty {
                    Text(
                        "\(viewModel.selectedUsers.count) participant\(viewModel.selectedUsers.count == 1 ? "" : "s") selected"
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

struct UserSelectionRow: View {
    let user: User
    let isSelected: Bool

    var body: some View {
        HStack {
            if let url = user.profileImageURL {
                AsyncImage(url: url) { image in
                    ProfilePhotoView(
                        image: image, name: user.name, size: 40,
                        placeholderColor: user.placeholderColor)
                } placeholder: {
                    ProfilePhotoView(
                        image: nil, name: user.name, size: 40,
                        placeholderColor: user.placeholderColor)
                }
            } else {
                ProfilePhotoView(
                    image: nil, name: user.name, size: 40, placeholderColor: user.placeholderColor)
            }

            Text(user.name)
                .font(.headline)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ThreadDetailsView: View {
    @Binding var threadName: String
    @Binding var apiKey: String
    @ObservedObject var viewModel: CreateThreadViewModel
    @State private var showError = false
    @State private var assistantName = ""
    @State private var customInstructions = ""
    let dismiss: DismissAction

    var body: some View {
        ThreadSettingsForm(
            threadName: $threadName,
            apiKey: $apiKey,
            assistantName: $assistantName,
            customInstructions: $customInstructions,
            showDangerZone: false,
            showParticipantsAndAssistant: false,
            autoFocusThreadName: true,
            onClearAPIKey: { apiKey = "" },
            onSave: createThread,
            onDeleteThread: {},
            isSaving: viewModel.isCreatingThread,
            isSaveDisabled: threadName.isEmpty,
            chatId: UUID().uuidString
        )
        .navigationTitle("Thread Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError, presenting: viewModel.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            if let error = error as? CreateThreadViewModel.CreateThreadError {
                Text(error.localizedDescription)
            } else {
                Text(error.localizedDescription)
            }
        }
    }

    private func createThread() {
        Task {
            do {
                try await viewModel.createThread(
                    name: threadName,
                    apiKey: apiKey.isEmpty ? nil : apiKey,
                    assistantName: assistantName.isEmpty ? nil : assistantName,
                    customInstructions: customInstructions.isEmpty ? nil : customInstructions
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("ThreadDetailsView: Error creating thread: \(error.localizedDescription)")
                await MainActor.run {
                    showError = true
                }
            }
        }
    }
}
