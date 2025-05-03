import FirebaseFirestore
import Foundation

public struct User: Identifiable, Codable, Hashable {
    @DocumentID public var id: String?
    public let name: String
    public var email: String?
    public var profileImageURL: URL?
    public var lastLoginDate: Date
    public var deviceToken: String?
    public var fcmToken: String?
    public var placeholderColor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case profileImageURL
        case lastLoginDate
        case deviceToken
        case fcmToken
        case placeholderColor
    }

    public init(id: String, name: String, email: String? = nil, profileImageURL: URL? = nil) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email
        self.profileImageURL = profileImageURL
        self.lastLoginDate = Date()
        self.deviceToken = nil
        self.fcmToken = nil
        self.placeholderColor = Self.generatePlaceholderColor(for: name)
    }

    private static func generatePlaceholderColor(for name: String) -> String {
        let colors: [String] = [
            "red", "orange", "yellow", "green", "blue", "purple", "pink", "indigo",
        ]

        var hash = 0
        for char in name.utf8 {
            hash = Int(char) &+ (hash << 6) &+ (hash << 16) &- hash
        }

        return colors[abs(hash) % colors.count]
    }

    // Computed property to ensure we always have a valid ID
    public var userId: String {
        return id ?? UUID().uuidString
    }

    // MARK: - Hashable Conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }

    public static func == (lhs: User, rhs: User) -> Bool {
        return lhs.userId == rhs.userId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode the ID first
        self.id = try container.decodeIfPresent(String.self, forKey: .id)

        // Decode and validate name
        let decodedName = try container.decode(String.self, forKey: .name)
        let trimmedName = decodedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Name cannot be empty"
                )
            )
        }
        self.name = trimmedName

        // Decode optional fields
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.deviceToken = try container.decodeIfPresent(String.self, forKey: .deviceToken)
        self.fcmToken = try container.decodeIfPresent(String.self, forKey: .fcmToken)

        // Handle URL decoding
        if let urlString = try container.decodeIfPresent(String.self, forKey: .profileImageURL) {
            self.profileImageURL = URL(string: urlString)
        } else {
            self.profileImageURL = nil
        }

        // Handle Date decoding with fallback
        if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: .lastLoginDate) {
            self.lastLoginDate = timestamp.dateValue()
        } else {
            self.lastLoginDate = Date()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .name)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(profileImageURL?.absoluteString, forKey: .profileImageURL)
        try container.encode(Timestamp(date: lastLoginDate), forKey: .lastLoginDate)
        try container.encodeIfPresent(deviceToken, forKey: .deviceToken)
        try container.encodeIfPresent(fcmToken, forKey: .fcmToken)
        try container.encodeIfPresent(placeholderColor, forKey: .placeholderColor)
    }
}
