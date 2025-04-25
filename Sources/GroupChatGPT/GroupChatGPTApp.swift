//
//  GroupChatGPTApp.swift
//  GroupChatGPT
//
//  Created by Gabriel Valdivia on 4/24/25.
//

import FirebaseCore
import SwiftUI

@main
struct GroupChatGPTApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            NavigationView {
                ChatView()
            }
        }
    }
}
