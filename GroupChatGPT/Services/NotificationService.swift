import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import SwiftUI
import UserNotifications

@MainActor
class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var isNotificationsAuthorized = false
    private let db = Firestore.firestore()

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(
            options: options)

        isNotificationsAuthorized = granted

        // Register for remote notifications on the main thread
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func scheduleMessageNotification(
        threadId: String, threadName: String, senderName: String, messageText: String
    ) async {
        guard isNotificationsAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = threadName
        content.subtitle = senderName
        content.body = messageText
        content.sound = .default
        content.threadIdentifier = threadId

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Error scheduling notification: \(error.localizedDescription)")
        }
    }

    func updateDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        guard let userId = Auth.auth().currentUser?.uid else { return }

        Task {
            do {
                try await db.collection("users").document(userId).updateData([
                    "deviceToken": tokenString
                ])
            } catch {
                print("Error updating device token: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Handle notification taps here
        let userInfo = response.notification.request.content.userInfo
        print("Notification tapped with userInfo: \(userInfo)")
    }
}
