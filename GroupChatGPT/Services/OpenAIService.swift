import Foundation

enum OpenAIError: Error {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
    case networkError(Error)
    case maxRetriesExceeded
}

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession

    init(apiKey: String) {
        self.apiKey = apiKey

        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 1

        self.session = URLSession(configuration: config)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func generateResponse(to message: String) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                [
                    "role": "system",
                    "content":
                        "You are a helpful assistant in a group chat. Keep your responses concise and conversational.",
                ],
                ["role": "user", "content": message],
            ],
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
