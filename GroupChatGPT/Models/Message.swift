import FirebaseFirestore
import Foundation

public struct Message: Identifiable, Codable, Equatable {
    @DocumentID public var id: String?
    public let senderId: String
    public let senderName: String
    public let text: String
    public let timestamp: Date
    public var isFromGPT: Bool

    // Custom ID for SwiftUI ForEach
    public var messageId: String {
        id ?? UUID().uuidString
    }

    public init(
        id: String? = nil, senderId: String, senderName: String, text: String, timestamp: Date,
        isFromGPT: Bool
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.isFromGPT = isFromGPT
    }

    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.senderId == rhs.senderId && lhs.senderName == rhs.senderName
            && lhs.text == rhs.text && lhs.timestamp == rhs.timestamp
            && lhs.isFromGPT == rhs.isFromGPT
    }
}
