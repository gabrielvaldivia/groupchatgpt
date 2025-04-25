import FirebaseFirestore
import Foundation
import OpenAI

enum OpenAIError: Error {
    case invalidURL
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse(Int)
    case decodingError(Error)
    case noChoicesReturned
    case apiError(String)
}

class OpenAIService {
    private let apiKey: String
    private let openAI: OpenAI

    init(apiKey: String) {
        self.apiKey = apiKey
        self.openAI = OpenAI(apiToken: apiKey)
        print("OpenAIService initialized with key prefix: \(String(apiKey.prefix(7)))...")
    }

    func generateResponse(to message: String, withHistory messages: [Message] = []) async throws
        -> String
    {
        print("🔍 Starting generateResponse with message: \(message)")
        print("📝 Chat history count: \(messages.count)")

        // Validate API key format - accepting project API keys
        guard apiKey.hasPrefix("sk-") else {
            print("❌ Invalid API key format - must start with sk-")
            throw OpenAIError.invalidAPIKey
        }

        // Convert previous messages to OpenAI format
        let historyMessages = messages.map { message -> Chat in
            return Chat(
                role: message.isFromGPT ? .assistant : .user,
                content: message.text
            )
        }

        // Combine system message, history, and current message
        var apiMessages: [Chat] = [
            Chat(
                role: .system,
                content:
                    "You are a helpful assistant in a group chat. Keep your responses concise and conversational. You have access to the chat history to provide more contextual responses."
            )
        ]

        // Add history messages
        apiMessages.append(contentsOf: historyMessages)

        // Add the current message
        apiMessages.append(Chat(role: .user, content: message))

        print("📤 Preparing API request with \(apiMessages.count) messages")

        do {
            print("🚀 Making API request to OpenAI...")
            let query = ChatQuery(
                model: .gpt3_5Turbo,
                messages: apiMessages,
                maxTokens: 150
            )
            print("📋 Query details:")
            print("   - Model: gpt-3.5-turbo")
            print("   - Messages count: \(apiMessages.count)")
            print("   - Max tokens: 150")

            let result = try await openAI.chats(query: query)
            print("✅ Received response from OpenAI")

            guard let choice = result.choices.first,
                let content = choice.message.content
            else {
                print("❌ No content in response choices")
                throw OpenAIError.noChoicesReturned
            }

            print("✨ Successfully generated response")
            return content
        } catch let error as OpenAIError {
            print("❌ OpenAI specific error: \(error)")
            throw error
        } catch {
            print("❌ Network or other error: \(error)")
            print("Error details: \(String(describing: error))")
            if let nsError = error as NSError? {
                print("NSError domain: \(nsError.domain)")
                print("NSError code: \(nsError.code)")
                print("NSError description: \(nsError.localizedDescription)")
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                    print("Underlying error: \(underlyingError)")
                }
            }
            throw OpenAIError.networkError(error)
        }
    }
}
