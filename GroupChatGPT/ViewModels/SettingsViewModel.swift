import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey: String {
        didSet {
            Settings.apiKey = apiKey
            OpenAIService.shared.configure(withApiKey: apiKey)
        }
    }

    private let db = Firestore.firestore()
    private let openAIService = OpenAIService.shared

    init() {
        self.apiKey = Settings.apiKey
        openAIService.configure(withApiKey: apiKey)
    }

    var isValidAPIKey: Bool {
        apiKey.starts(with: "sk-") && apiKey.count > 20
    }

    func clearAPIKey() {
        apiKey = ""
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
}
