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
            guard var uiImage = UIImage(data: data) else { return }

            // Normalize orientation
            if uiImage.imageOrientation != .up {
                UIGraphicsBeginImageContextWithOptions(uiImage.size, false, uiImage.scale)
                uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
                if let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                    UIGraphicsEndImageContext()
                    uiImage = normalizedImage
                } else {
                    UIGraphicsEndImageContext()
                }
            }

            // First create a square crop from the center
            let sideLength = min(uiImage.size.width, uiImage.size.height)
            let xOffset = (uiImage.size.width - sideLength) / 2
            let yOffset = (uiImage.size.height - sideLength) / 2
            let cropRect = CGRect(x: xOffset, y: yOffset, width: sideLength, height: sideLength)

            guard let cgImage = uiImage.cgImage?.cropping(to: cropRect) else { return }
            let squareImage = UIImage(cgImage: cgImage)

            // Then resize the square image
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
            let resizedImage = renderer.image { context in
                squareImage.draw(in: CGRect(origin: .zero, size: CGSize(width: 400, height: 400)))
            }

            guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else { return }
            guard imageData.count < 900 * 1024 else {
                showError = true
                errorMessage = "Image is too large. Please choose a smaller image."
                return
            }

            self.imageData = imageData
            self.profileImage = Image(uiImage: resizedImage)
        } catch {
            showError = true
            errorMessage = "Failed to load image: \(error.localizedDescription)"
        }
    }

    func saveChanges() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            // Create a complete user object with all required fields
            let user = User(
                id: userId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: nil,
                profileImageURL: nil
            )

            var userData = try JSONEncoder().encode(user)
            var dict = try JSONSerialization.jsonObject(with: userData) as? [String: Any] ?? [:]

            // Add the profile image if it was updated
            if let imageData = imageData {
                let base64String = imageData.base64EncodedString()
                let imageURLString = "data:image/jpeg;base64,\(base64String)"
                dict["profileImageURL"] = imageURLString
            }

            // Always use setData to ensure all required fields are present
            try await db.collection("users").document(userId).setData(dict, merge: true)

            // Update original name to reflect the saved state
            originalName = name
        } catch {
            showError = true
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }
}

// MARK: - UIImage Extension
extension UIImage {
    func fixOrientation() -> UIImage {
        if imageOrientation == .up { return self }

        var transform = CGAffineTransform.identity

        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }

        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }

        guard let cgImage = self.cgImage,
            let colorSpace = cgImage.colorSpace,
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: cgImage.bitmapInfo.rawValue
            )
        else { return self }

        context.concatenate(transform)

        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }

        guard let newCGImage = context.makeImage() else { return self }
        return UIImage(cgImage: newCGImage)
    }
}
