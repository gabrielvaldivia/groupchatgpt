import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var newMessageText = ""

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private let openAIService = OpenAIService.shared
    private let thread: Thread
    private let authService: AuthenticationService

    init(thread: Thread) {
        self.thread = thread
        self.authService = .shared

        // Configure OpenAI with thread's API key
        if let apiKey = thread.apiKey {
            openAIService.configure(chatId: thread.threadId, apiKey: apiKey)
        }

        setupMessagesListener()
    }

    deinit {
        listenerRegistration?.remove()
    }

    private func setupMessagesListener() {
        print("Setting up messages listener...")
        // Cancel any existing listener
        listenerRegistration?.remove()

        listenerRegistration = db.collection("threads")
            .document(thread.threadId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("Error listening for messages: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot else {
                    print("No snapshot received")
                    return
                }

                let newMessages = snapshot.documents.compactMap { document -> Message? in
                    do {
                        var message = try document.data(as: Message.self)
                        if message.id == nil {
                            message.id = document.documentID
                        }
                        return message
                    } catch {
                        print("Error decoding message: \(error.localizedDescription)")
                        return nil
                    }
                }

                print("Received \(newMessages.count) messages")
                self.messages = newMessages
            }
    }

    func sendMessage() {
        guard !newMessageText.isEmpty, let currentUser = authService.currentUser else { return }

        let messageText = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        newMessageText = ""

        let message = Message(
            messageId: UUID().uuidString,
            senderId: currentUser.userId,
            senderName: currentUser.name,
            text: messageText,
            timestamp: Date()
        )

        // Save to Firestore
        Task {
            do {
                try await db.collection("threads").document(thread.threadId)
                    .collection("messages")
                    .document(message.messageId)
                    .setData(from: message)

                // Generate AI response if API key is configured
                if let apiKey = thread.apiKey {
                    let aiResponse = try await openAIService.generateResponse(
                        to: "\(message.senderName): \(message.text)", chatId: thread.threadId)

                    let aiMessage = Message(
                        messageId: UUID().uuidString,
                        senderId: "ai",
                        senderName: "Assistant",
                        text: aiResponse,
                        timestamp: Date()
                    )

                    try await db.collection("threads").document(thread.threadId)
                        .collection("messages")
                        .document(aiMessage.messageId)
                        .setData(from: aiMessage)
                }
            } catch {
                print("Error sending message: \(error)")
            }
        }
    }

    func isFromCurrentUser(_ message: Message) -> Bool {
        return message.senderId == authService.currentUser?.userId
    }

    func clearAllMessages() async {
        print("Clearing all messages...")
        do {
            // Get all messages in the thread
            let snapshot = try await db.collection("threads")
                .document(thread.threadId)
                .collection("messages")
                .getDocuments()

            // Delete each message
            for document in snapshot.documents {
                try await document.reference.delete()
            }

            // Clear OpenAI conversation history
            openAIService.clearConversationHistory(for: thread.threadId)

            print("Successfully cleared all messages")
        } catch {
            print("Error clearing messages: \(error)")
        }
    }
}
