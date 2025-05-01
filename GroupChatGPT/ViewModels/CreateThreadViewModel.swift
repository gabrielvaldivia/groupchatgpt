import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class CreateThreadViewModel: ObservableObject {
    @Published var availableUsers: [User] = []
    @Published var selectedUsers = Set<User>()
    @Published var error: Error?
    @Published var isLoading = false
    @Published var isCreatingThread = false

    enum CreateThreadError: LocalizedError {
        case noAuthenticatedUser
        case noParticipantsSelected
        case invalidThreadName
        case invalidApiKey
        case firestoreError(String)

        var errorDescription: String? {
            switch self {
            case .noAuthenticatedUser:
                return "No authenticated user found"
            case .noParticipantsSelected:
                return "Please select at least one participant"
            case .invalidThreadName:
                return "Please enter a valid thread name"
            case .invalidApiKey:
                return "The provided API key format is invalid"
            case .firestoreError(let message):
                return "Database error: \(message)"
            }
        }
    }

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    init() {
        loadUsers()
    }

    deinit {
        listenerRegistration?.remove()
    }

    private func loadUsers() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("CreateThreadViewModel: No current user ID")
            return
        }

        isLoading = true

        // Remove any existing listener
        listenerRegistration?.remove()

        print("CreateThreadViewModel: Starting to load users")

        listenerRegistration = db.collection("users")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                self.isLoading = false

                if let error = error {
                    print(
                        "CreateThreadViewModel: Error loading users: \(error.localizedDescription)")
                    self.error = error
                    return
                }

                guard let snapshot = snapshot else {
                    print("CreateThreadViewModel: No snapshot received")
                    return
                }

                print("CreateThreadViewModel: Processing \(snapshot.documents.count) documents")

                self.availableUsers = snapshot.documents.compactMap { document -> User? in
                    do {
                        // First try to decode the document
                        if var user = try? document.data(as: User.self) {
                            // Always use the document ID as the user ID
                            user.id = document.documentID

                            // Skip the current user
                            if user.userId != currentUserId {
                                print(
                                    "CreateThreadViewModel: Successfully loaded user \(user.name) with ID \(user.userId)"
                                )
                                return user
                            }
                        }
                        return nil
                    } catch {
                        print(
                            "CreateThreadViewModel: Error decoding user document \(document.documentID): \(error.localizedDescription)"
                        )
                        return nil
                    }
                }.sorted { $0.name < $1.name }

                print("CreateThreadViewModel: Loaded \(self.availableUsers.count) available users")
                self.availableUsers.forEach { user in
                    print(
                        "CreateThreadViewModel: Available user: \(user.name) (ID: \(user.userId))")
                }
            }
    }

    func toggleUser(_ user: User) {
        if selectedUsers.contains(user) {
            selectedUsers.remove(user)
        } else {
            selectedUsers.insert(user)
        }
        print("CreateThreadViewModel: Selected users count: \(selectedUsers.count)")
    }

    func isUserSelected(_ user: User) -> Bool {
        selectedUsers.contains(user)
    }

    private func validateInputs(name: String, apiKey: String?) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CreateThreadError.invalidThreadName
        }

        guard !selectedUsers.isEmpty else {
            throw CreateThreadError.noParticipantsSelected
        }

        if let apiKey = apiKey {
            // Basic OpenAI API key format validation (sk-...)
            guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "sk-") else {
                throw CreateThreadError.invalidApiKey
            }
        }
    }

    func createThread(name: String, emoji: String, apiKey: String?) async throws {
        print("CreateThreadViewModel: Starting thread creation")

        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("CreateThreadViewModel: No authenticated user")
            throw CreateThreadError.noAuthenticatedUser
        }

        // Validate inputs
        try validateInputs(name: name, apiKey: apiKey)
        print("CreateThreadViewModel: Inputs validated")

        isCreatingThread = true
        defer { isCreatingThread = false }

        // Include current user in participants
        var participantIds = selectedUsers.map { $0.userId }
        participantIds.append(currentUserId)

        print("CreateThreadViewModel: Creating thread with \(participantIds.count) participants")

        // Create the thread
        let thread = Thread(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: emoji,
            participants: participantIds,
            createdBy: currentUserId,
            apiKey: apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            // Save to Firestore
            let threadRef = db.collection("threads").document()
            print("CreateThreadViewModel: Saving thread to Firestore")
            try await threadRef.setData(from: thread)
            print("CreateThreadViewModel: Thread created successfully")
        } catch {
            print("CreateThreadViewModel: Error creating thread: \(error.localizedDescription)")
            self.error = CreateThreadError.firestoreError(error.localizedDescription)
            throw error
        }
    }

    func clearError() {
        error = nil
    }
}
