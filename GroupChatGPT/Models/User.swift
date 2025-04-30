import FirebaseFirestore
import Foundation

public struct User: Identifiable, Codable {
    @DocumentID public var id: String?
    public let name: String
    public var email: String?
    public var profileImageURL: URL?
    public var lastLoginDate: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case profileImageURL
        case lastLoginDate
    }

    public init(id: String, name: String, email: String? = nil, profileImageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.profileImageURL = profileImageURL
        self.lastLoginDate = Date()
    }

    // Computed property to ensure we always have a valid ID
    public var userId: String {
        return id ?? UUID().uuidString
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)

        // Ensure we have a name, fallback to "User" if missing
        if let name = try container.decodeIfPresent(String.self, forKey: .name) {
            self.name = name
        } else {
            self.name = "User"
        }

        self.email = try container.decodeIfPresent(String.self, forKey: .email)

        // Handle URL decoding
        if let urlString = try container.decodeIfPresent(String.self, forKey: .profileImageURL) {
            self.profileImageURL = URL(string: urlString)
        } else {
            self.profileImageURL = nil
        }

        // Handle Date decoding with fallback to current date
        if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: .lastLoginDate) {
            self.lastLoginDate = timestamp.dateValue()
        } else {
            self.lastLoginDate = Date()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(profileImageURL?.absoluteString, forKey: .profileImageURL)
        try container.encode(Timestamp(date: lastLoginDate), forKey: .lastLoginDate)
    }
}
