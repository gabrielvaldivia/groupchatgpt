import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // Set messaging delegate
        Messaging.messaging().delegate = self

        // Request notification authorization
        Task {
            do {
                try await NotificationService.shared.requestAuthorization()
            } catch {
                print("Error requesting notification authorization: \(error.localizedDescription)")
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        NotificationService.shared.updateDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("Firebase registration token: \(token)")

        // Store FCM token in Firestore
        if let userId = Auth.auth().currentUser?.uid {
            Task {
                do {
                    try await Firestore.firestore().collection("users").document(userId).updateData(
                        [
                            "fcmToken": token
                        ])
                } catch {
                    print("Error updating FCM token: \(error.localizedDescription)")
                }
            }
        }
    }
}
