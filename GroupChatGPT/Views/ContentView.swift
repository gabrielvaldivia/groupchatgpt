import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthenticationService

    var body: some View {
        NavigationView {
            UserListView()
        }
    }
}
