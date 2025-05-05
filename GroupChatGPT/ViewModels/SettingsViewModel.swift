import FirebaseAuth
import FirebaseFirestore
import Foundation
import PhotosUI
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isDeleting = false
    @Published var threadName: String = ""
    @Published var assistantName: String = ""
    @Published var customInstructions: String = ""
    @Published var isUpdating = false
    @Published var participants: [User] = []
    @Published var isLoadingParticipants = false
    @Published var assistantProfileImage: Image?
    @Published var assistantProfileImageData: Data?
    @Published var assistantProfileImageURL: String?
    @Published var assistantPhotoPickerItem: PhotosPickerItem? {
        didSet { Task { await loadAssistantPhoto() } }
    }
    private let chatId: String
    private let openAIService = OpenAIService.shared
    private let db = Firestore.firestore()
    private let threadListViewModel = ThreadListViewModel.shared
    private var threadListener: ListenerRegistration?

    init(chatId: String) {
        self.chatId = chatId
        self.apiKey = ""
        self.threadName = ""
        self.assistantName = ""
        self.customInstructions = ""

        // Fetch initial thread data
        fetchInitialThreadData()
        setupThreadListener()
        loadParticipants()
    }

    private func fetchInitialThreadData() {
        db.collection("threads").document(chatId).getDocument { [weak self] snapshot, error in
            guard let self = self,
                let snapshot = snapshot,
                let thread = try? snapshot.data(as: Thread.self)
            else {
                return
            }

            Task { @MainActor in
                self.threadName = thread.name
                self.apiKey = thread.apiKey ?? ""
                self.assistantName = thread.assistantName ?? "ChatGPT"
                self.customInstructions = thread.customInstructions ?? ""
                self.assistantProfileImageURL = thread.assistantProfileImageURL
                if let urlString = thread.assistantProfileImageURL,
                    let url = URL(string: urlString), !urlString.isEmpty
                {
                    if urlString.hasPrefix("data:") {
                        if let image = self.loadBase64Image(from: urlString) {
                            self.assistantProfileImage = image
                        }
                    } else {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            if let uiImage = UIImage(data: data) {
                                self.assistantProfileImage = Image(uiImage: uiImage)
                            }
                        } catch {
                            print("Error loading assistant profile image: \(error)")
                        }
                    }
                } else {
                    self.assistantProfileImage = nil
                }
            }
        }
    }

    deinit {
        threadListener?.remove()
    }

    private func setupThreadListener() {
        print("Setting up thread listener in settings...")
        threadListener?.remove()

        threadListener = db.collection("threads").document(chatId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("Error listening for thread updates: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot, snapshot.exists,
                    let thread = try? snapshot.data(as: Thread.self)
                else {
                    return
                }

                // Update UI with latest thread data
                self.threadName = thread.name
                self.apiKey = thread.apiKey ?? ""
                self.assistantName = thread.assistantName ?? ""
                self.customInstructions = thread.customInstructions ?? ""
            }
    }

    func updateThread(name: String) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isUpdating = true
        defer { isUpdating = false }

        try await db.collection("threads").document(chatId).updateData([
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
    }

    func updateAPIKey(_ newKey: String) {
        Task {
            do {
                try await db.collection("threads").document(chatId).setData(
                    [
                        "apiKey": newKey
                    ], merge: true)
            } catch {
                print("Error saving API key: \(error)")
            }
        }
    }

    func clearAPIKey() {
        Task {
            do {
                try await db.collection("threads").document(chatId).updateData([
                    "apiKey": FieldValue.delete()
                ])
            } catch {
                print("Error clearing API key: \(error)")
            }
        }
    }

    func clearAllMessages() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        do {
            // Get all chats where the current user is a participant
            let snapshot = try await db.collection("chats").getDocuments()

            for chatDoc in snapshot.documents {
                let chatId = chatDoc.documentID

                // Only clear chats that involve the current user
                if chatId.contains(currentUserId) {
                    // Get all messages in this chat
                    let messagesSnapshot = try await db.collection("chats")
                        .document(chatId)
                        .collection("messages")
                        .getDocuments()

                    // Delete each message
                    for messageDoc in messagesSnapshot.documents {
                        try await messageDoc.reference.delete()
                    }

                    // Clear OpenAI conversation history for this chat
                    openAIService.clearConversationHistory(for: chatId)
                }
            }

            print("Successfully cleared all messages")
        } catch {
            print("Error clearing messages: \(error)")
        }
    }

    func deleteThread() async throws {
        isDeleting = true
        defer { isDeleting = false }

        try await threadListViewModel.deleteThread(
            Thread(id: chatId, name: "", participants: [], createdBy: "")
        )
    }

    func updateAssistantName(_ name: String) {
        Task {
            do {
                try await db.collection("threads").document(chatId).setData(
                    [
                        "assistantName": name.trimmingCharacters(in: .whitespacesAndNewlines)
                    ], merge: true)

                // Update OpenAI service with new assistant name
                openAIService.configureAssistantName(chatId: chatId, name: name)
            } catch {
                print("Error updating assistant name: \(error)")
            }
        }
    }

    func updateCustomInstructions(_ instructions: String) {
        Task {
            do {
                let trimmedInstructions = instructions.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                try await db.collection("threads").document(chatId).setData(
                    [
                        "customInstructions": trimmedInstructions
                    ], merge: true)

                // Update OpenAI service with new instructions
                openAIService.configureCustomInstructions(
                    chatId: chatId, instructions: trimmedInstructions)
            } catch {
                print("Error updating custom instructions: \(error)")
            }
        }
    }

    private func loadParticipants() {
        Task {
            do {
                isLoadingParticipants = true
                defer { isLoadingParticipants = false }

                let threadDoc = try await db.collection("threads").document(chatId).getDocument()
                guard let thread = try? threadDoc.data(as: Thread.self) else { return }

                var loadedParticipants: [User] = []
                for userId in thread.participants {
                    let userDoc = try await db.collection("users").document(userId).getDocument()
                    if let user = try? userDoc.data(as: User.self) {
                        loadedParticipants.append(user)
                    }
                }

                await MainActor.run {
                    participants = loadedParticipants
                }
            } catch {
                print("Error loading participants: \(error)")
            }
        }
    }

    func addParticipant(_ user: User) {
        Task {
            do {
                let threadRef = db.collection("threads").document(chatId)
                let threadDoc = try await threadRef.getDocument()
                guard var thread = try? threadDoc.data(as: Thread.self) else { return }
                if !thread.participants.contains(user.userId) {
                    thread.participants.append(user.userId)
                    try threadRef.setData(from: thread, merge: true)
                    await MainActor.run { self.loadParticipants() }
                }
            } catch {
                print("Error adding participant: \(error)")
            }
        }
    }

    func removeParticipant(_ user: User) {
        Task {
            do {
                let threadRef = db.collection("threads").document(chatId)
                let threadDoc = try await threadRef.getDocument()
                guard var thread = try? threadDoc.data(as: Thread.self) else { return }
                thread.participants.removeAll { $0 == user.userId }
                try threadRef.setData(from: thread, merge: true)
                await MainActor.run { self.loadParticipants() }
            } catch {
                print("Error removing participant: \(error)")
            }
        }
    }

    func updateAssistantProfileImage() async {
        guard let imageData = assistantProfileImageData else { return }
        let base64String = imageData.base64EncodedString()
        let imageURLString = "data:image/jpeg;base64,\(base64String)"
        do {
            try await db.collection("threads").document(chatId).updateData([
                "assistantProfileImageURL": imageURLString
            ])
            self.assistantProfileImageURL = imageURLString
        } catch {
            print("Error updating assistant profile image: \(error)")
        }
    }

    private func loadBase64Image(from dataURL: String) -> Image? {
        guard let base64String = dataURL.components(separatedBy: ",").last,
            let imageData = Data(base64Encoded: base64String),
            let uiImage = UIImage(data: imageData)
        else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private func loadAssistantPhoto() async {
        guard let item = assistantPhotoPickerItem else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: data) else { return }
            let resizedImage = await normalizeAndResizeImage(uiImage)
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else { return }
            guard imageData.count < 900 * 1024 else {
                return
            }
            await MainActor.run {
                self.assistantProfileImageData = imageData
                self.assistantProfileImage = Image(uiImage: resizedImage)
            }
            await updateAssistantProfileImage()
        } catch {
            print("Failed to load assistant photo: \(error)")
        }
    }

    private func normalizeAndResizeImage(_ uiImage: UIImage) async -> UIImage {
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
        let sideLength = min(normalizedImage.size.width, normalizedImage.size.height)
        let xOffset = (normalizedImage.size.width - sideLength) / 2
        let yOffset = (normalizedImage.size.height - sideLength) / 2
        let cropRect = CGRect(x: xOffset, y: yOffset, width: sideLength, height: sideLength)
        guard let cgImage = normalizedImage.cgImage?.cropping(to: cropRect) else {
            return normalizedImage
        }
        let squareImage = UIImage(cgImage: cgImage)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        return renderer.image { context in
            squareImage.draw(in: CGRect(origin: .zero, size: CGSize(width: 400, height: 400)))
        }
    }
}
