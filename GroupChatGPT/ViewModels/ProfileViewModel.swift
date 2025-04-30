import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var selectedItem: PhotosPickerItem? {
        didSet { Task { await loadImage() } }
    }
    @Published var profileImage: Image?
    @Published var showError = false
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private var originalName: String = ""
    private var imageData: Data?
    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?

    var isEdited: Bool {
        name != originalName || imageData != nil
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    deinit {
        userListener?.remove()
    }

    func loadProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        // Remove any existing listener
        userListener?.remove()

        // Set up a real-time listener for the user document
        userListener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    self.showError = true
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let snapshot = snapshot, snapshot.exists,
                    let user = try? snapshot.data(as: User.self)
                else {
                    return
                }

                // Update the UI
                self.name = user.name
                self.originalName = user.name

                // Load profile image if it exists
                if let profileImageURL = user.profileImageURL {
                    Task {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: profileImageURL)
                            if let uiImage = UIImage(data: data) {
                                self.profileImage = Image(uiImage: uiImage)
                            }
                        } catch {
                            print("Error loading profile image: \(error)")
                        }
                    }
                }

                self.isLoading = false
            }
    }

    private func loadImage() async {
        guard let item = selectedItem else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: data) else { return }

            // Resize image to a small size suitable for profile photo
            let targetSize = CGSize(width: 200, height: 200)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

            let resizedImage = renderer.image { context in
                uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            guard let resizedData = resizedImage.jpegData(compressionQuality: 0.7) else { return }
            // Ensure the image data is under 900KB (Firestore limit is 1MB)
            guard resizedData.count < 900 * 1024 else {
                showError = true
                errorMessage = "Image is too large. Please choose a smaller image."
                return
            }

            imageData = resizedData
            profileImage = Image(uiImage: resizedImage)
        } catch {
            showError = true
            errorMessage = "Failed to load image: \(error.localizedDescription)"
        }
    }

    func saveChanges() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            var updateData: [String: Any] = [:]

            // Update name if changed
            if name != originalName {
                updateData["name"] = name
            }

            // Update image if selected
            if let imageData = imageData {
                // Convert image data to base64 string
                let base64String = imageData.base64EncodedString()
                let imageURLString = "data:image/jpeg;base64,\(base64String)"
                updateData["profileImageURL"] = imageURLString
            }

            if !updateData.isEmpty {
                let docRef = db.collection("users").document(userId)

                // First try to get the document
                let doc = try await docRef.getDocument()

                if doc.exists {
                    // Update existing document
                    try await docRef.updateData(updateData)
                } else {
                    // Create new document with all required fields
                    var newUserData = updateData
                    newUserData["name"] = name
                    newUserData["lastLoginDate"] = Timestamp(date: Date())
                    try await docRef.setData(newUserData, merge: true)
                }
            }
        } catch {
            showError = true
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }
}
