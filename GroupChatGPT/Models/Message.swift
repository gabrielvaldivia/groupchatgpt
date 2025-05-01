import FirebaseFirestore
import Foundation

struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    let messageId: String
    let senderId: String
    let senderName: String
    let text: String
    let timestamp: Date

    var userId: String {
        return id ?? messageId
    }
}
