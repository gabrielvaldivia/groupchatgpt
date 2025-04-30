//
//  GroupChatGPTApp.swift
//  GroupChatGPT
//
//  Created by Gabriel Valdivia on 4/24/25.
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import SwiftUI

@main
struct GroupChatGPTApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthenticationService.shared

    var body: some Scene {
        WindowGroup {
            NavigationView {
                if authService.isAuthenticated {
                    UserListView()
                        .environmentObject(authService)
                } else {
                    SignInView()
                        .environmentObject(authService)
                }
            }
            .navigationViewStyle(.stack)
        }
    }
}
