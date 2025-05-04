import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ThreadListViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var lastReadTimestamps: [String: Double] = [:]

    static let shared = ThreadListViewModel()

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    init() {
        setupThreadsListener()
    }

    deinit {
        listenerRegistration?.remove()
    }

    private func setupThreadsListener() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("ThreadListViewModel: No current user ID")
            return
        }

        print("ThreadListViewModel: Setting up listener for user \(currentUserId)")
        isLoading = true

        // Cancel any existing listener
        listenerRegistration?.remove()

        let query = db.collection("threads")
            .whereField("participants", arrayContains: currentUserId)

        listenerRegistration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            self.isLoading = false

            if let error = error {
                print("ThreadListViewModel: Error fetching threads: \(error.localizedDescription)")
                self.error = error
                return
            }

            guard let snapshot = snapshot else {
                print("ThreadListViewModel: No snapshot received")
                return
            }

            print("ThreadListViewModel: Received \(snapshot.documents.count) threads")

            // First, decode the threads without last messages
            let initialThreads = snapshot.documents.compactMap { document -> Thread? in
                do {
                    var thread = try document.data(as: Thread.self)
                    return thread
                } catch {
                    print(
                        "ThreadListViewModel: Error decoding thread: \(error.localizedDescription)")
                    return nil
                }
            }

            // Then fetch last messages for each thread
            Task { [self] in
                var updatedThreads = initialThreads
                for (index, thread) in initialThreads.enumerated() {
                    if let threadId = thread.id {
                        do {
                            let messagesSnapshot = try await self.db.collection("threads")
                                .document(threadId)
                                .collection("messages")
                                .order(by: "timestamp", descending: true)
                                .limit(to: 1)
                                .getDocuments()

                            if let lastMessageDoc = messagesSnapshot.documents.first,
                                let message = try? lastMessageDoc.data(as: Message.self)
                            {
                                updatedThreads[index].lastMessage = message.text
                                updatedThreads[index].lastMessageTimestamp = message.timestamp
                            }
                        } catch {
                            print(
                                "ThreadListViewModel: Error fetching last message: \(error.localizedDescription)"
                            )
                        }
                    }
                }

                // Update the threads array with last messages
                await MainActor.run {
                    self.threads = updatedThreads
                    // Sort threads by unread status and last message timestamp
                    self.threads.sort {
                        let unreadA = self.isThreadUnread($0)
                        let unreadB = self.isThreadUnread($1)
                        if unreadA != unreadB {
                            return unreadA
                        }
                        // fallback: sort by last message timestamp (descending)
                        let tsA = $0.lastMessageTimestamp?.timeIntervalSince1970 ?? 0
                        let tsB = $1.lastMessageTimestamp?.timeIntervalSince1970 ?? 0
                        return tsA > tsB
                    }
                }
            }
        }
    }

    func createThread(name: String, participants: [String], apiKey: String?) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
            )
        }

        print("ThreadListViewModel: Creating thread with \(participants.count) participants")

        // Add current user to participants if not already included
        var allParticipants = Set(participants)
        allParticipants.insert(currentUserId)

        let thread = Thread(
            name: name,
            participants: Array(allParticipants),
            createdBy: currentUserId,
            apiKey: apiKey,
            assistantName: "ChatGPT"  // Set default assistant name
        )

        let threadRef = db.collection("threads").document()
        try threadRef.setData(from: thread)
        print("ThreadListViewModel: Thread created with ID: \(threadRef.documentID)")

        // Manually add the thread to our local array to ensure immediate UI update
        var newThread = thread
        threads.insert(newThread, at: 0)  // Add to the beginning since it's newest
    }

    func deleteThread(_ thread: Thread) async throws {
        guard let threadId = thread.id else { return }

        // Delete all messages in the thread
        let messagesSnapshot = try await db.collection("threads")
            .document(threadId)
            .collection("messages")
            .getDocuments()

        for doc in messagesSnapshot.documents {
            try await doc.reference.delete()
        }

        // Delete the thread document
        try await db.collection("threads").document(threadId).delete()

        // Remove from local array immediately
        await MainActor.run {
            threads.removeAll { $0.id == threadId }
        }
    }

    // MARK: - Unread Message Tracking
    func markThreadAsRead(_ thread: Thread) {
        guard let threadId = thread.id, let lastMessageTimestamp = thread.lastMessageTimestamp
        else {
            print("ThreadListViewModel: Cannot mark thread as read - missing id or timestamp")
            return
        }
        let timestamp = lastMessageTimestamp.timeIntervalSince1970
        print("ThreadListViewModel: Marking thread \(threadId) as read with timestamp \(timestamp)")
        UserDefaults.standard.set(timestamp, forKey: "lastRead_\(threadId)")
        lastReadTimestamps[threadId] = timestamp
        DispatchQueue.main.async {
            print("ThreadListViewModel: Sending objectWillChange for thread \(threadId)")
            self.objectWillChange.send()
        }
    }

    func isThreadUnread(_ thread: Thread) -> Bool {
        guard let threadId = thread.id, let lastMessageTimestamp = thread.lastMessageTimestamp
        else {
            print("ThreadListViewModel: Cannot check unread status - missing id or timestamp")
            return false
        }
        let lastReadTimestamp = UserDefaults.standard.double(forKey: "lastRead_\(threadId)")
        let isUnread = lastMessageTimestamp.timeIntervalSince1970 > lastReadTimestamp
        print(
            "ThreadListViewModel: Thread \(threadId) unread check - lastMessage: \(lastMessageTimestamp.timeIntervalSince1970), lastRead: \(lastReadTimestamp), isUnread: \(isUnread)"
        )
        return isUnread
    }
}
