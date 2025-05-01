import SwiftUI

struct ThreadListView: View {
    @StateObject private var viewModel = ThreadListViewModel()
    @State private var showingCreateThread = false
    @State private var showingProfile = false
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        ZStack {
            if viewModel.threads.isEmpty {
                VStack(spacing: 16) {
                    Text("No Threads")
                        .font(.headline)
                    Text("Create a new thread to start chatting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(viewModel.threads) { thread in
                        NavigationLink {
                            ChatView(thread: thread)
                        } label: {
                            ThreadRow(thread: thread)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            if let index = indexSet.first {
                                try? await viewModel.deleteThread(viewModel.threads[index])
                            }
                        }
                    }
                }
            }

            // Floating Action Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showingCreateThread = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4, y: 2)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Threads")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingProfile = true
                } label: {
                    Image(systemName: "person.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sign Out") {
                    authService.signOut()
                }
            }
        }
        .sheet(isPresented: $showingCreateThread) {
            CreateThreadView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(authService)
        }
    }
}

struct ThreadRow: View {
    let thread: Thread

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(thread.name)
                    .font(.headline)
                Text("\(thread.participants.count) participants")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
