import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var newMessageText = ""

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private let openAIService: OpenAIService

    init() {
        self.openAIService = OpenAIService(apiKey: Config.openAIKey)
        signInAnonymously()
        setupMessagesListener()
    }

    func isFromCurrentUser(_ message: Message) -> Bool {
        return message.senderId == Auth.auth().currentUser?.uid
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

    func setupMessagesListener() {
        print("Setting up messages listener...")
        // Cancel any existing listener
        listenerRegistration?.remove()

        listenerRegistration = db.collection("messages")
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
                        // Ensure the message has the Firestore document ID
                        if message.id == nil {
                            message.id = document.documentID
                        }
                        print("Decoded message: \(String(describing: message))")
                        return message
                    } catch {
                        print("Error decoding message: \(error.localizedDescription)")
                        return nil
                    }
                }

                print("Received \(newMessages.count) messages")
                DispatchQueue.main.async {
                    self.messages = newMessages
                }
            }
    }

    func sendMessage() {
        print("Attempting to send message: \(newMessageText)")

        guard !newMessageText.isEmpty else {
            print("Message text is empty")
            return
        }

        guard let currentUser = Auth.auth().currentUser else {
            print("No authenticated user found")
            return
        }

        let messageText = newMessageText  // Create a local copy
        self.newMessageText = ""  // Clear the text field immediately

        let message = Message(
            id: nil,  // Firestore will generate this
            senderId: currentUser.uid,
            senderName: currentUser.email ?? "Anonymous",
            text: messageText,
            timestamp: Date(),
            isFromGPT: false
        )

        do {
            let docRef = try db.collection("messages").addDocument(from: message)
            print("Message sent successfully with ID: \(docRef.documentID)")

            // Check for ChatGPT mention
            if messageText.lowercased().contains("@chatgpt") {
                print("ChatGPT mentioned, triggering response")
                Task {
                    await handleChatGPTMention(originalMessage: message)
                }
            }
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }

    private func handleChatGPTMention(originalMessage: Message) async {
        do {
            // Remove the @chatgpt mention from the message
            let userMessage = originalMessage.text.replacingOccurrences(
                of: "@chatgpt", with: "", options: [.caseInsensitive])

            // Get the last 10 messages before this one for context
            let contextMessages = messages.prefix(messages.count - 1).suffix(10).map { $0 }

            // Get response from OpenAI with context
            let response = try await openAIService.generateResponse(
                to: userMessage, withHistory: contextMessages)

            let gptMessage = Message(
                id: nil,
                senderId: "chatgpt",
                senderName: "ChatGPT",
                text: response,
                timestamp: Date(),
                isFromGPT: true
            )

            do {
                try db.collection("messages").addDocument(from: gptMessage)
                print("ChatGPT response sent successfully")
            } catch {
                print("Error saving GPT message to Firestore: \(error)")
                throw error
            }
        } catch let error as OpenAIError {
            print("OpenAI error: \(error)")

            // Create a more specific error message based on the error type
            let errorText: String
            switch error {
            case .invalidAPIKey:
                errorText = "Invalid API key. Please check your OpenAI API key configuration."
            case .networkError:
                errorText =
                    "Sorry, there was a network error. Please check your internet connection and try again."
            case .apiError(let message):
                errorText = "Sorry, there was an error: \(message)"
            case .invalidURL:
                errorText =
                    "Sorry, there was a configuration error. Please contact the administrator."
            case .invalidResponse(let code):
                errorText = "Sorry, received an invalid response (code: \(code)). Please try again."
            case .decodingError:
                errorText = "Sorry, there was an error processing the response. Please try again."
            case .noChoicesReturned:
                errorText = "Sorry, no response was generated. Please try again."
            }

            let errorMessage = Message(
                id: nil,
                senderId: "chatgpt",
                senderName: "ChatGPT",
                text: errorText,
                timestamp: Date(),
                isFromGPT: true
            )

            do {
                try db.collection("messages").addDocument(from: errorMessage)
            } catch {
                print("Error saving error message to Firestore: \(error)")
            }
        } catch {
            print("Unexpected error: \(error)")

            let errorMessage = Message(
                id: nil,
                senderId: "chatgpt",
                senderName: "ChatGPT",
                text: "Sorry, an unexpected error occurred. Please try again.",
                timestamp: Date(),
                isFromGPT: true
            )

            do {
                try db.collection("messages").addDocument(from: errorMessage)
            } catch {
                print("Error saving error message to Firestore: \(error)")
            }
        }
    }
}
