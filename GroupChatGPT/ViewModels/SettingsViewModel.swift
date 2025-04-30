import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey: String {
        didSet {
            Settings.apiKey = apiKey
        }
    }

    private let chatViewModel = ChatViewModel()

    init() {
        self.apiKey = Settings.apiKey
    }

    var isValidAPIKey: Bool {
        apiKey.starts(with: "sk-") && apiKey.count > 20
    }

    func clearAPIKey() {
        apiKey = ""
    }

    func clearAllMessages() async {
        await chatViewModel.clearAllMessages()
    }
}
