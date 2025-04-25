import FirebaseFirestore
import Foundation

struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    let senderId: String
    let senderName: String
    let text: String
    let timestamp: Date
    var isFromGPT: Bool

    // Custom ID for SwiftUI ForEach
    var messageId: String {
        id ?? UUID().uuidString
    }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId
        case senderName
        case text
        case timestamp
        case isFromGPT
    }
}
