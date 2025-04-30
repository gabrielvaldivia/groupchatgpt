import Foundation

public struct User: Identifiable, Codable {
    public let id: String
    public let name: String
    public var email: String?
    public var profileImageURL: URL?
    public var lastLoginDate: Date

    public init(id: String, name: String, email: String? = nil, profileImageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.profileImageURL = profileImageURL
        self.lastLoginDate = Date()
    }
}
