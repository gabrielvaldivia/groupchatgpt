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
    @Published private(set) var displayImage: Image?
    @Published var showError = false
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var placeholderColor: String?

    private var originalName: String = ""
    private var imageData: Data?
    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?
    private var isSaving = false
    private var hasRemovedPhoto = false

    var isEdited: Bool {
        name != originalName || imageData != nil || hasRemovedPhoto
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateProfileImage(_ image: Image?) {
        displayImage = image
    }

    deinit {
        userListener?.remove()
    }

    func loadProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        if isSaving { return }

        isLoading = true
        hasRemovedPhoto = false

        // Remove any existing listener
        userListener?.remove()

        // Set up a real-time listener for the user document
        userListener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if self.isSaving { return }

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
                self.placeholderColor = user.placeholderColor

                // Load profile image if it exists
                if let profileImageURL = user.profileImageURL {
                    Task {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: profileImageURL)
                            if let uiImage = UIImage(data: data) {
                                self.displayImage = Image(uiImage: uiImage)
                            }
                        } catch {
                            print("Error loading profile image: \(error)")
                        }
                    }
                } else {
                    self.displayImage = nil
                }

                self.isLoading = false
            }
    }

    private func loadImage() async {
        guard let item = selectedItem else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: data) else { return }

            // Normalize orientation and resize
            let resizedImage = await normalizeAndResizeImage(uiImage)
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else { return }
            guard imageData.count < 900 * 1024 else {
                showError = true
                errorMessage = "Image is too large. Please choose a smaller image."
                return
            }

            await MainActor.run {
                self.imageData = imageData
                self.displayImage = Image(uiImage: resizedImage)
            }
        } catch {
            await MainActor.run {
                showError = true
                errorMessage = "Failed to load image: \(error.localizedDescription)"
            }
        }
    }

    private func normalizeAndResizeImage(_ uiImage: UIImage) async -> UIImage {
        // First normalize orientation
        var normalizedImage = uiImage
        if uiImage.imageOrientation != .up {
            UIGraphicsBeginImageContextWithOptions(uiImage.size, false, uiImage.scale)
            uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
            if let newImage = UIGraphicsGetImageFromCurrentImageContext() {
                UIGraphicsEndImageContext()
                normalizedImage = newImage
            } else {
                UIGraphicsEndImageContext()
            }
        }

        // Create square crop
        let sideLength = min(normalizedImage.size.width, normalizedImage.size.height)
        let xOffset = (normalizedImage.size.width - sideLength) / 2
        let yOffset = (normalizedImage.size.height - sideLength) / 2
        let cropRect = CGRect(x: xOffset, y: yOffset, width: sideLength, height: sideLength)

        guard let cgImage = normalizedImage.cgImage?.cropping(to: cropRect) else {
            return normalizedImage
        }
        let squareImage = UIImage(cgImage: cgImage)

        // Resize to final dimensions
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        return renderer.image { context in
            squareImage.draw(in: CGRect(origin: .zero, size: CGSize(width: 400, height: 400)))
        }
    }

    func saveChanges() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        defer {
            isSaving = false
            hasRemovedPhoto = false
        }

        do {
            // First update the name if it changed
            if name != originalName {
                try await db.collection("users").document(userId).updateData([
                    "name": name.trimmingCharacters(in: .whitespacesAndNewlines)
                ])
                originalName = name
            }

            // Then handle the profile image
            if let imageData = imageData {
                // New image was added
                let base64String = imageData.base64EncodedString()
                let imageURLString = "data:image/jpeg;base64,\(base64String)"
                try await db.collection("users").document(userId).updateData([
                    "profileImageURL": imageURLString
                ])
            } else if hasRemovedPhoto {
                // Photo was removed
                try await db.collection("users").document(userId).updateData([
                    "profileImageURL": FieldValue.delete()
                ])
            }

            // Clear image data after successful save
            self.imageData = nil
        } catch {
            showError = true
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }

    func removePhoto() {
        self.displayImage = nil
        self.imageData = nil
        self.selectedItem = nil
        self.hasRemovedPhoto = true
    }

    func resetState() {
        hasRemovedPhoto = false
        imageData = nil
        selectedItem = nil
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
