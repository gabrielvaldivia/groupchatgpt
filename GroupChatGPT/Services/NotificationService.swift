import Combine
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
        checkAuthorizationStatus()
    }

    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isNotificationsAuthorized = settings.authorizationStatus == .authorized
                print("Notification authorization status: \(settings.authorizationStatus.rawValue)")
            }
        }
    }

    func requestAuthorization() async throws {
        print("Requesting notification authorization...")
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(
            options: options)

        isNotificationsAuthorized = granted
        print("Notification authorization granted: \(granted)")

        if granted {
            // Register for remote notifications on the main thread
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func scheduleMessageNotification(
        threadId: String, threadName: String, senderName: String, messageText: String
    ) async {
        print("Attempting to schedule notification for thread: \(threadId)")
        print("App state: \(UIApplication.shared.applicationState.rawValue)")

        guard isNotificationsAuthorized else {
            print("Notifications not authorized, requesting permission...")
            do {
                try await requestAuthorization()
                if !isNotificationsAuthorized {
                    print("User denied notification permissions")
                    return
                }
            } catch {
                print("Error requesting notification authorization: \(error.localizedDescription)")
                return
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = threadName
        content.subtitle = senderName
        content.body = messageText
        content.sound = .default
        content.threadIdentifier = threadId
        content.userInfo = [
            "threadId": threadId,
            "type": "message",
        ]

        // Create a trigger that delivers the notification immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create the request with a unique identifier
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            // Remove any pending notifications for this thread
            let center = UNUserNotificationCenter.current()
            let requests = try await center.pendingNotificationRequests()
            for request in requests {
                if request.content.threadIdentifier == threadId {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                }
            }

            // Add the new notification
            try await center.add(request)
            print("Successfully scheduled notification for thread: \(threadId)")
            print("Notification content: \(content.title) - \(content.subtitle): \(content.body)")
            print("App state during scheduling: \(UIApplication.shared.applicationState.rawValue)")
        } catch {
            print("Error scheduling notification: \(error.localizedDescription)")
        }
    }

    func updateDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Received device token: \(tokenString)")

        guard let userId = Auth.auth().currentUser?.uid else {
            print("No current user found for device token update")
            return
        }

        Task {
            do {
                try await db.collection("users").document(userId).updateData([
                    "deviceToken": tokenString
                ])
                print("Successfully updated device token for user: \(userId)")
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
        let state = UIApplication.shared.applicationState
        print("Notification received while app is in state: \(state.rawValue)")
        print(
            "Notification content: \(notification.request.content.title) - \(notification.request.content.subtitle): \(notification.request.content.body)"
        )

        // Show notification if app is not active
        if state != .active {
            print("Showing notification banner")
            return [.banner, .sound, .badge]
        }

        // If app is active, show notification regardless of view state
        // This ensures the user is notified of new messages even if they're in the app
        print("App is active, showing notification")
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        print("Notification tapped with userInfo: \(userInfo)")
        print(
            "Notification content: \(response.notification.request.content.title) - \(response.notification.request.content.subtitle): \(response.notification.request.content.body)"
        )
    }
}
