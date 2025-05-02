import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var newMessageText = ""

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private var threadListener: ListenerRegistration?
    private let openAIService = OpenAIService.shared
    private let notificationService = NotificationService.shared
    private var thread: Thread
    private let authService: AuthenticationService

    init(thread: Thread) {
        self.thread = thread
        self.authService = AuthenticationService.shared

        // Configure OpenAI with thread's API key and settings
        if let apiKey = thread.apiKey {
            openAIService.configure(chatId: thread.threadId, apiKey: apiKey)
        }
        if let assistantName = thread.assistantName {
            openAIService.configureAssistantName(chatId: thread.threadId, name: assistantName)
        }
        openAIService.configureCustomInstructions(
            chatId: thread.threadId, instructions: thread.customInstructions)

        setupThreadListener()
        setupMessagesListener()
    }

    deinit {
        listenerRegistration?.remove()
        threadListener?.remove()
    }

    private func setupThreadListener() {
        print("Setting up thread listener...")
        threadListener?.remove()

        threadListener = db.collection("threads").document(thread.threadId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("Error listening for thread updates: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot, snapshot.exists,
                    let updatedThread = try? snapshot.data(as: Thread.self)
                else {
                    return
                }

                // Update thread reference with latest data
                self.thread = updatedThread
                self.thread.id = snapshot.documentID

                // Update OpenAI configuration if settings changed
                if let apiKey = updatedThread.apiKey {
                    print("Updating API key configuration")
                    self.openAIService.configure(chatId: self.thread.threadId, apiKey: apiKey)
                }
                if let assistantName = updatedThread.assistantName {
                    print("Updating assistant name configuration")
                    self.openAIService.configureAssistantName(
                        chatId: self.thread.threadId, name: assistantName)
                }
                self.openAIService.configureCustomInstructions(
                    chatId: self.thread.threadId, instructions: updatedThread.customInstructions)
            }
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

                // Schedule notifications for new messages
                if let currentUserId = Auth.auth().currentUser?.uid {
                    for message in newMessages {
                        // Only notify for messages from others
                        if message.senderId != currentUserId {
                            Task {
                                await self.notificationService.scheduleMessageNotification(
                                    threadId: self.thread.threadId,
                                    threadName: self.thread.name,
                                    senderName: message.senderName,
                                    messageText: message.text
                                )
                            }
                        }
                    }
                }
            }
    }

    func sendMessage() {
        guard !newMessageText.isEmpty, let currentUser = authService.currentUser else {
            print("DEBUG: Cannot send message - no current user")
            return
        }

        guard let userId = Auth.auth().currentUser?.uid else {
            print("DEBUG: No Firebase Auth user ID")
            return
        }

        print("DEBUG: Sending message as user: \(userId)")
        let messageText = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        newMessageText = ""

        let message = Message(
            messageId: UUID().uuidString,
            senderId: userId,
            senderName: currentUser.name,
            text: messageText,
            timestamp: Date()
        )
        print("DEBUG: Created message with senderId: \(message.senderId)")

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
                        senderName: thread.assistantName ?? "ChatGPT",
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
        guard let userId = Auth.auth().currentUser?.uid else {
            print("DEBUG: No Firebase Auth user ID")
            return false
        }
        print("DEBUG: Comparing message.senderId: \(message.senderId) with userId: \(userId)")
        return message.senderId == userId
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
