import FirebaseFirestore
import Foundation

enum OpenAIError: Error {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
    case networkError(Error)
    case maxRetriesExceeded
    case notAddressed
}

class OpenAIService {
    static let shared = OpenAIService()

    private var apiKeys: [String: String] = [:]  // chatId: apiKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession
    private var conversationHistories: [String: [[String: String]]] = [:]
    private let maxHistoryLength = 20  // Maximum number of messages to keep in history

    // Add properties for assistant name configuration
    private var assistantNames: [String: String] = [:]  // chatId: assistantName
    private let defaultAssistantName = "ChatGPT"

    private var customInstructions: [String: String] = [:]  // chatId: instructions

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 1

        self.session = URLSession(configuration: config)
    }

    func configure(chatId: String, apiKey: String) {
        apiKeys[chatId] = apiKey
    }

    func configureCustomInstructions(chatId: String, instructions: String?) {
        if let instructions = instructions {
            customInstructions[chatId] = instructions
        } else {
            customInstructions.removeValue(forKey: chatId)
        }
        clearConversationHistory(for: chatId)
    }

    func getAPIKey(for chatId: String) -> String? {
        return apiKeys[chatId]
    }

    func clearAPIKey(for chatId: String) {
        apiKeys.removeValue(forKey: chatId)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // Add method to configure assistant name
    func configureAssistantName(chatId: String, name: String) {
        assistantNames[chatId] = name
        // Reset conversation history to update system message with new name
        clearConversationHistory(for: chatId)
    }

    func clearAssistantName(for chatId: String) {
        assistantNames.removeValue(forKey: chatId)
        // Reset conversation history to update system message with default name
        clearConversationHistory(for: chatId)
    }

    // Add method to get current assistant name
    func getAssistantName(for chatId: String) -> String {
        return assistantNames[chatId] ?? defaultAssistantName
    }

    private func getOrCreateHistory(for chatId: String) -> [[String: String]] {
        if conversationHistories[chatId] == nil {
            let assistantName = getAssistantName(for: chatId)
            let instructions = customInstructions[chatId]

            var systemMessage = """
                You are \(assistantName), a helpful assistant in a group chat. Keep your responses concise and conversational.
                You should remember and reference information from previous messages in the conversation.
                Each message includes the sender's name in the format "Name: message".
                When responding, acknowledge the user by their name if it was mentioned in previous messages.
                You MUST strictly follow these additional instructions for ALL your responses:
                """

            if let instructions = instructions, !instructions.isEmpty {
                systemMessage += "\n\(instructions)"
            }

            conversationHistories[chatId] = [
                [
                    "role": "system",
                    "content": systemMessage,
                ]
            ]
        }
        return conversationHistories[chatId]!
    }

    func addToHistory(chatId: String, role: String, content: String) {
        var history = getOrCreateHistory(for: chatId)
        history.append(["role": role, "content": content])

        // Keep history within size limit, but always preserve system message
        if history.count > maxHistoryLength {
            let systemMessage = history[0]
            history = [systemMessage] + history.suffix(maxHistoryLength - 1)
        }

        conversationHistories[chatId] = history
    }

    private func isMessageAddressedToChatGPT(_ message: String, chatId: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        let assistantName = getAssistantName(for: chatId).lowercased()

        return lowercasedMessage.contains("@\(assistantName)")
            || lowercasedMessage.contains("hey \(assistantName)")
    }

    func generateResponse(to message: String, chatId: String) async throws -> String {
        // Check if the message is addressed to the assistant
        guard isMessageAddressedToChatGPT(message, chatId: chatId) else {
            throw OpenAIError.notAddressed
        }

        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }

        guard let apiKey = apiKeys[chatId] else {
            throw OpenAIError.apiError("No API key configured for this chat")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // Add the new user message to history
        addToHistory(chatId: chatId, role: "user", content: message)

        let history = getOrCreateHistory(for: chatId)

        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": history,
            "temperature": 0.7,
            "max_tokens": 150,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                if let errorResponse = try? JSONDecoder().decode(
                    OpenAIErrorResponse.self, from: data)
                {
                    throw OpenAIError.apiError(errorResponse.error.message)
                } else {
                    throw OpenAIError.apiError(
                        "API request failed with status code \(httpResponse.statusCode)")
                }
            }

            let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            guard let content = result.choices.first?.message.content else {
                throw OpenAIError.decodingError
            }

            // Add the assistant's response to history
            addToHistory(chatId: chatId, role: "assistant", content: content)

            return content.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    throw OpenAIError.apiError(
                        "No internet connection. Please check your connection and try again.")
                case .timedOut:
                    throw OpenAIError.apiError("Request timed out. Please try again.")
                case .networkConnectionLost:
                    throw OpenAIError.apiError("Network connection was lost. Please try again.")
                default:
                    throw OpenAIError.networkError(error)
                }
            }
            throw OpenAIError.networkError(error)
        }
    }

    func clearConversationHistory(for chatId: String) {
        let assistantName = getAssistantName(for: chatId)
        let instructions = customInstructions[chatId]

        var systemMessage = """
            You are \(assistantName), a helpful assistant in a group chat. Keep your responses concise and conversational.
            You should remember and reference information from previous messages in the conversation.
            Each message includes the sender's name in the format "Name: message".
            When responding, acknowledge the user by their name if it was mentioned in previous messages.
            You MUST strictly follow these additional instructions for ALL your responses:
            """

        if let instructions = instructions, !instructions.isEmpty {
            systemMessage += "\n\(instructions)"
        }

        conversationHistories[chatId] = [
            [
                "role": "system",
                "content": systemMessage,
            ]
        ]
    }
}

// Response structures
struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

struct OpenAIErrorResponse: Codable {
    struct ErrorDetails: Codable {
        let message: String
        let type: String?
        let code: String?
    }
    let error: ErrorDetails
}
