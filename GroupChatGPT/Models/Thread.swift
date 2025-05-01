import FirebaseFirestore
import Foundation

struct Thread: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let emoji: String
    let participants: [String]  // User IDs
    let createdAt: Date
    let createdBy: String  // User ID
    var apiKey: String?

    var threadId: String {
        return id ?? UUID().uuidString
    }

    init(
        id: String? = nil,
        name: String,
        emoji: String,
        participants: [String],
        createdBy: String,
        apiKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.participants = participants
        self.createdBy = createdBy
        self.createdAt = Date()
        self.apiKey = apiKey
    }
}
