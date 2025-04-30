import Foundation

struct Settings {
    private static let apiKeyKey = "openai_api_key"

    static var apiKey: String {
        get {
            UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
        }
    }
}
