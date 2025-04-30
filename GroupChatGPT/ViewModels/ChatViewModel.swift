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
    private let otherUser: User
    private var chatId: String = ""

    init(otherUser: User) {
        self.otherUser = otherUser
        openAIService.configure(withApiKey: Settings.apiKey)
        signInAnonymously()
        setupMessagesListener()
    }

    deinit {
        listenerRegistration?.remove()
    }

    private func signInAnonymously() {
        Auth.auth().signInAnonymously { result, error in
            if let error = error {
                print("Error signing in: \(error.localizedDescription)")
                return
            }
            print("Successfully signed in anonymously")
        }
    }

    private func setupMessagesListener() {
        print("Setting up messages listener...")
        // Cancel any existing listener
        listenerRegistration?.remove()

        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("No current user")
            return
        }

        // Create a chat ID that's the same regardless of who started the chat
        chatId = [currentUserId, otherUser.id].sorted().joined(separator: "_")

        listenerRegistration = db.collection("chats")
            .document(chatId)
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
        guard !newMessageText.isEmpty,
            let currentUser = Auth.auth().currentUser
        else {
            return
        }

        let messageText = newMessageText
        self.newMessageText = ""

        let message = Message(
            id: nil,
            senderId: currentUser.uid,
            senderName: currentUser.email ?? "Anonymous",
            text: messageText,
            timestamp: Date(),
            isFromGPT: false
        )

        do {
            try db.collection("chats")
                .document(chatId)
                .collection("messages")
                .addDocument(from: message)

            print("Message sent successfully")

            // Check if the message mentions @chatgpt
            if messageText.lowercased().contains("@chatgpt") {
                Task {
                    do {
                        // Remove the @chatgpt mention from the message
                        let cleanMessage = messageText.replacingOccurrences(
                            of: "@chatgpt", with: "", options: [.caseInsensitive])

                        // Add recent messages as context
                        let recentMessages = messages.suffix(5)  // Get last 5 messages for context
                        for msg in recentMessages {
                            openAIService.addToHistory(
                                chatId: chatId,
                                role: msg.isFromGPT ? "assistant" : "user",
                                content: "\(msg.senderName): \(msg.text)"
                            )
                        }

                        // Generate response from OpenAI
                        let response = try await openAIService.generateResponse(
                            to: cleanMessage, chatId: chatId)

                        // Create and send the GPT response message
                        let gptMessage = Message(
                            id: nil,
                            senderId: "chatgpt",
                            senderName: "ChatGPT",
                            text: response,
                            timestamp: Date(),
                            isFromGPT: true
                        )

                        try db.collection("chats")
                            .document(chatId)
                            .collection("messages")
                            .addDocument(from: gptMessage)

                        print("ChatGPT response sent successfully")
                    } catch {
                        print("Error generating ChatGPT response: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }

    func isFromCurrentUser(_ message: Message) -> Bool {
        return message.senderId == Auth.auth().currentUser?.uid
    }

    func clearAllMessages() async {
        print("Clearing all messages...")
        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                return
            }

            let chatId = [currentUserId, otherUser.id].sorted().joined(separator: "_")

            // Get all messages in the chat
            let snapshot = try await db.collection("chats")
                .document(chatId)
                .collection("messages")
                .getDocuments()

            // Delete each message
            for document in snapshot.documents {
                try await document.reference.delete()
            }

            // Clear OpenAI conversation history
            openAIService.clearConversationHistory(for: chatId)

            print("Successfully cleared all messages")
        } catch {
            print("Error clearing messages: \(error)")
        }
    }
}
// Helper extension for Message
extension Message {
    func asDictionary() throws -> [String: Any] {
        return [
            "senderId": senderId,
            "senderName": senderName,
            "text": text,
            "timestamp": timestamp,
            "isFromGPT": isFromGPT,
        ]
    }
}
