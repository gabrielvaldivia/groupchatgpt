import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var newMessageText = ""
    private var hasInitialLoad = false
    private var isAppActive = true
    private var isViewingThread = true
    private var lastMessageId: String?

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

        // Set up app state observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(viewDidDisappear),
            name: NSNotification.Name("ViewDidDisappear"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(viewDidAppear),
            name: NSNotification.Name("ViewDidAppear"),
            object: nil
        )

        setupThreadListener()
        setupMessagesListener()
    }

    deinit {
        listenerRegistration?.remove()
        threadListener?.remove()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidBecomeActive() {
        print("App became active")
        isAppActive = true

        // Refresh the listener when coming back to foreground
        print("Refreshing message listener")
        setupMessagesListener()
    }

    @objc private func appDidEnterBackground() {
        print("App entered background")
        isAppActive = false

        // Ensure we're still listening for messages in the background
        if listenerRegistration == nil {
            print("Re-establishing message listener in background")
            setupMessagesListener()
        }
    }

    @objc private func viewDidDisappear() {
        print("View disappeared")
        isViewingThread = false
    }

    @objc private func viewDidAppear() {
        print("View appeared")
        isViewingThread = true
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
        hasInitialLoad = false

        print("Current thread ID: \(thread.threadId)")
        print("Current user ID: \(Auth.auth().currentUser?.uid ?? "nil")")
        print("App state: \(UIApplication.shared.applicationState.rawValue)")

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

                print("Received snapshot with \(snapshot.documents.count) documents")
                print("Current message count: \(self.messages.count)")
                print("hasInitialLoad: \(self.hasInitialLoad)")
                print("isViewingThread: \(self.isViewingThread)")
                print("isAppActive: \(self.isAppActive)")
                print("App state: \(UIApplication.shared.applicationState.rawValue)")

                let newMessages = snapshot.documents.compactMap { document -> Message? in
                    do {
                        var message = try document.data(as: Message.self)
                        if message.id == nil {
                            message.id = document.documentID
                        }
                        print("Decoded message: \(message.senderName): \(message.text)")
                        return message
                    } catch {
                        print("Error decoding message: \(error.localizedDescription)")
                        return nil
                    }
                }

                print("Decoded \(newMessages.count) messages")

                // Only schedule notifications for messages that arrive after initial load and when not viewing the thread
                if let currentUserId = Auth.auth().currentUser?.uid {
                    let appState = UIApplication.shared.applicationState
                    let shouldNotify =
                        self.hasInitialLoad
                        && (!self.isViewingThread || !self.isAppActive || appState != .active)

                    print("Notification decision:")
                    print("- hasInitialLoad: \(self.hasInitialLoad)")
                    print("- isViewingThread: \(self.isViewingThread)")
                    print("- isAppActive: \(self.isAppActive)")
                    print("- App state: \(appState.rawValue)")
                    print("- Should notify: \(shouldNotify)")

                    if shouldNotify {
                        print("Conditions met for notification scheduling")
                        // After initial load and not viewing thread or app is in background, notify for new messages
                        let currentMessageIds = Set(self.messages.map { $0.messageId })
                        print("Current message IDs: \(currentMessageIds)")

                        for message in newMessages {
                            if message.senderId != currentUserId
                                && !currentMessageIds.contains(message.messageId)
                            {
                                print("New message from other user: \(message.senderName)")
                                print("Message ID: \(message.messageId)")
                                print("Message text: \(message.text)")
                                print(
                                    "Scheduling notification in background state: \(appState.rawValue)"
                                )
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
                    } else if !self.hasInitialLoad {
                        // This is the initial load, mark it as complete
                        print("Initial message load complete")
                        self.hasInitialLoad = true
                    } else {
                        print("Notification conditions not met:")
                        print("- hasInitialLoad: \(self.hasInitialLoad)")
                        print("- isViewingThread: \(self.isViewingThread)")
                        print("- isAppActive: \(self.isAppActive)")
                        print("- App state: \(appState.rawValue)")
                    }
                } else {
                    print("No current user ID found")
                }

                self.messages = newMessages
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
                try db.collection("threads").document(thread.threadId)
                    .collection("messages")
                    .document(message.messageId)
                    .setData(from: message)

                // Generate AI response if API key is configured
                if thread.apiKey != nil {
                    let aiResponse = try await openAIService.generateResponse(
                        to: "\(message.senderName): \(message.text)", chatId: thread.threadId)

                    let aiMessage = Message(
                        messageId: UUID().uuidString,
                        senderId: "ai",
                        senderName: thread.assistantName ?? "ChatGPT",
                        text: aiResponse,
                        timestamp: Date()
                    )

                    try db.collection("threads").document(thread.threadId)
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
