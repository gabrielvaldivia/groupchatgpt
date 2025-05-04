import FirebaseFirestore
import Foundation

struct Thread: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    var participants: [String]  // User IDs
    let createdAt: Date
    let createdBy: String  // User ID
    var apiKey: String?
    var assistantName: String?  // Add this field for custom assistant name
    var customInstructions: String?  // Custom instructions for the AI assistant
    var lastMessage: String?  // Preview of the last message

    var threadId: String {
        return id ?? UUID().uuidString
    }

    init(
        id: String? = nil,
        name: String,
        participants: [String],
        createdBy: String,
        apiKey: String? = nil,
        assistantName: String? = nil,
        customInstructions: String? = nil,
        lastMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.participants = participants
        self.createdBy = createdBy
        self.createdAt = Date()
        self.apiKey = apiKey
        self.assistantName = assistantName
        self.customInstructions = customInstructions
        self.lastMessage = lastMessage
    }
}
