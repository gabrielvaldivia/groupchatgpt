import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct ChatView: View {
    let thread: Thread
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    @State private var showingSettings = false
    @EnvironmentObject private var authService: AuthenticationService

    init(thread: Thread) {
        self.thread = thread
        self._viewModel = StateObject(wrappedValue: ChatViewModel(thread: thread))
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: viewModel.isFromCurrentUser(message)
                            )
                            .id(message.messageId)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.messageId, anchor: .bottom)
                        }
                    }
                }
            }

            // Input field container
            HStack(spacing: 12) {
                // Message input field
                HStack(spacing: 8) {
                    TextField("Message", text: $viewModel.newMessageText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($isFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            if !viewModel.newMessageText.isEmpty {
                                viewModel.sendMessage()
                            }
                        }

                    // Send button
                    Button(action: {
                        viewModel.sendMessage()
                        isFocused = false
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(viewModel.newMessageText.isEmpty ? .gray : .blue)
                    }
                    .disabled(viewModel.newMessageText.isEmpty)
                    .padding(.trailing, 8)
                }
                .background(Color(.systemGray6))
                .cornerRadius(20)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.systemGray5))
                    .opacity(0.5),
                alignment: .top
            )
        }
        .navigationTitle("\(thread.emoji) \(thread.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(chatId: thread.threadId)
        }
    }
}

struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    @State private var messageHeight: CGFloat = 0

    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.senderName)
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        GeometryReader { geometry in
                            let color = isFromCurrentUser ? Color.blue : Color(.systemGray5)
                            color
                                .cornerRadius(min(messageHeight * 0.5, 20))
                                .onAppear {
                                    messageHeight = geometry.size.height
                                }
                        }
                    )
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
            }
            .padding(.horizontal, 4)

            if !isFromCurrentUser {
                Spacer()
            }
        }
    }
}
