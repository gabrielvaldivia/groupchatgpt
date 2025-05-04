import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct ParticipantsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingAddParticipant = false
    @State private var availableUsers: [User] = []
    @State private var isLoadingAvailableUsers = false
    private var currentUserId: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLoadingParticipants {
                ProgressView("Loading participants...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                List {
                    ForEach(viewModel.participants) { user in
                        HStack {
                            if let url = user.profileImageURL {
                                AsyncImage(url: url) { image in
                                    ProfilePhotoView(
                                        image: image,
                                        name: user.name,
                                        size: 28,
                                        placeholderColor: user.placeholderColor
                                    )
                                } placeholder: {
                                    ProfilePhotoView(
                                        image: nil,
                                        name: user.name,
                                        size: 28,
                                        placeholderColor: user.placeholderColor
                                    )
                                }
                            } else {
                                ProfilePhotoView(
                                    image: nil,
                                    name: user.name,
                                    size: 28,
                                    placeholderColor: user.placeholderColor
                                )
                            }
                            Text(user.name)
                                .font(.body)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color(.systemBackground))
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let user = viewModel.participants[index]
                            if user.userId != currentUserId {
                                viewModel.removeParticipant(user)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Participants")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    loadAvailableUsers()
                    showingAddParticipant = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddParticipant) {
            NavigationView {
                List(availableUsers) { user in
                    Button {
                        viewModel.addParticipant(user)
                        showingAddParticipant = false
                    } label: {
                        HStack {
                            if let url = user.profileImageURL {
                                AsyncImage(url: url) { image in
                                    ProfilePhotoView(
                                        image: image,
                                        name: user.name,
                                        size: 28,
                                        placeholderColor: user.placeholderColor
                                    )
                                } placeholder: {
                                    ProfilePhotoView(
                                        image: nil,
                                        name: user.name,
                                        size: 28,
                                        placeholderColor: user.placeholderColor
                                    )
                                }
                            } else {
                                ProfilePhotoView(
                                    image: nil,
                                    name: user.name,
                                    size: 28,
                                    placeholderColor: user.placeholderColor
                                )
                            }
                            Text(user.name)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color(.systemBackground))
                }
                .navigationTitle("Add Participant")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddParticipant = false }
                    }
                }
            }
        }
    }

    private func loadAvailableUsers() {
        guard let currentUserId = currentUserId else { return }
        isLoadingAvailableUsers = true
        let db = Firestore.firestore()
        db.collection("users").getDocuments { snapshot, error in
            isLoadingAvailableUsers = false
            guard let documents = snapshot?.documents else { return }
            let allUsers = documents.compactMap { try? $0.data(as: User.self) }
            let participantIds = Set(viewModel.participants.map { $0.userId })
            availableUsers = allUsers.filter { user in
                user.userId != currentUserId && !participantIds.contains(user.userId)
            }
        }
    }
}
