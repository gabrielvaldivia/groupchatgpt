import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isDeleting = false
    @Published var threadName: String = ""
    @Published var assistantName: String = ""
    @Published var customInstructions: String = ""
    @Published var isUpdating = false
    private let chatId: String
    private let openAIService = OpenAIService.shared
    private let db = Firestore.firestore()
    private let threadListViewModel = ThreadListViewModel.shared
    private var threadListener: ListenerRegistration?

    init(chatId: String) {
        self.chatId = chatId
        self.apiKey = ""
        self.threadName = ""
        self.assistantName = ""
        self.customInstructions = ""

        // Fetch initial thread data
        fetchInitialThreadData()
        setupThreadListener()
    }

    private func fetchInitialThreadData() {
        db.collection("threads").document(chatId).getDocument { [weak self] snapshot, error in
            guard let self = self,
                let snapshot = snapshot,
                let thread = try? snapshot.data(as: Thread.self)
            else {
                return
            }

            Task { @MainActor in
                self.threadName = thread.name
                self.apiKey = thread.apiKey ?? ""
                self.assistantName = thread.assistantName ?? ""
                self.customInstructions = thread.customInstructions ?? ""
            }
        }
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
                self.apiKey = thread.apiKey ?? ""
                self.assistantName = thread.assistantName ?? ""
                self.customInstructions = thread.customInstructions ?? ""
            }
    }

    func updateThread(name: String) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isUpdating = true
        defer { isUpdating = false }

        try await db.collection("threads").document(chatId).updateData([
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
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
            Thread(id: chatId, name: "", participants: [], createdBy: "")
        )
    }

    func updateAssistantName(_ name: String) {
        Task {
            do {
                try await db.collection("threads").document(chatId).setData(
                    [
                        "assistantName": name.trimmingCharacters(in: .whitespacesAndNewlines)
                    ], merge: true)

                // Update OpenAI service with new assistant name
                openAIService.configureAssistantName(chatId: chatId, name: name)
            } catch {
                print("Error updating assistant name: \(error)")
            }
        }
    }

    func updateCustomInstructions(_ instructions: String) {
        Task {
            do {
                let trimmedInstructions = instructions.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                try await db.collection("threads").document(chatId).setData(
                    [
                        "customInstructions": trimmedInstructions
                    ], merge: true)

                // Update OpenAI service with new instructions
                openAIService.configureCustomInstructions(
                    chatId: chatId, instructions: trimmedInstructions)
            } catch {
                print("Error updating custom instructions: \(error)")
            }
        }
    }
}
