import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isDeleting = false
    @Published var threadName: String = ""
    @Published var threadEmoji: String = ""
    @Published var isUpdating = false
    private let chatId: String
    private let openAIService = OpenAIService.shared
    private let db = Firestore.firestore()
    private let threadListViewModel = ThreadListViewModel.shared
    private var threadListener: ListenerRegistration?

    init(chatId: String) {
        self.chatId = chatId
        self.apiKey = openAIService.getAPIKey(for: chatId) ?? ""
        setupThreadListener()
    }

    deinit {
        threadListener?.remove()
    }

    private func setupThreadListener() {
        print("Setting up thread listener in settings...")
        threadListener?.remove()

        threadListener = db.collection("threads").document(chatId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("Error listening for thread updates: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot, snapshot.exists,
                    let thread = try? snapshot.data(as: Thread.self)
                else {
                    return
                }

                // Update UI with latest thread data
                self.threadName = thread.name
                self.threadEmoji = thread.emoji
                self.apiKey = thread.apiKey ?? ""

                // Configure OpenAI service
                if let apiKey = thread.apiKey {
                    self.openAIService.configure(chatId: self.chatId, apiKey: apiKey)
                }
            }
    }

    func updateThread(name: String, emoji: String) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isUpdating = true
        defer { isUpdating = false }

        let updates = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "emoji": emoji,
        ]

        try await db.collection("threads").document(chatId).updateData(updates)
    }

    func updateAPIKey(_ newKey: String) {
        Task {
            do {
                try await db.collection("threads").document(chatId).setData(
                    [
                        "apiKey": newKey
                    ], merge: true)
            } catch {
                print("Error saving API key: \(error)")
            }
        }
    }

    func clearAPIKey() {
        Task {
            do {
                try await db.collection("threads").document(chatId).updateData([
                    "apiKey": FieldValue.delete()
                ])
            } catch {
                print("Error clearing API key: \(error)")
            }
        }
    }

    func clearAllMessages() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        do {
            // Get all chats where the current user is a participant
            let snapshot = try await db.collection("chats").getDocuments()

            for chatDoc in snapshot.documents {
                let chatId = chatDoc.documentID

                // Only clear chats that involve the current user
                if chatId.contains(currentUserId) {
                    // Get all messages in this chat
                    let messagesSnapshot = try await db.collection("chats")
                        .document(chatId)
                        .collection("messages")
                        .getDocuments()

                    // Delete each message
                    for messageDoc in messagesSnapshot.documents {
                        try await messageDoc.reference.delete()
                    }

                    // Clear OpenAI conversation history for this chat
                    openAIService.clearConversationHistory(for: chatId)
                }
            }

            print("Successfully cleared all messages")
        } catch {
            print("Error clearing messages: \(error)")
        }
    }

    func deleteThread() async throws {
        isDeleting = true
        defer { isDeleting = false }

        try await threadListViewModel.deleteThread(
            Thread(id: chatId, name: "", emoji: "", participants: [], createdBy: ""))
    }
}
