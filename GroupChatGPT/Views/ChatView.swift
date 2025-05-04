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
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.messageId) {
                            index, message in
                            let showName =
                                index == 0
                                || viewModel.messages[index - 1].senderId != message.senderId
                            let topSpacing =
                                index == 0
                                ? 0
                                : (viewModel.messages[index - 1].senderId == message.senderId
                                    ? 4 : 12)
                            VStack(spacing: 0) {
                                Spacer().frame(height: CGFloat(topSpacing))
                                MessageBubble(
                                    message: message,
                                    isFromCurrentUser: viewModel.isFromCurrentUser(message),
                                    showSenderName: showName
                                )
                                .id(message.messageId)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.messageId, anchor: .bottom)
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
        .navigationTitle(thread.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            print("ChatView: View appeared for thread \(thread.id ?? "unknown")")
            print(
                "ChatView: Thread lastMessageTimestamp: \(thread.lastMessageTimestamp?.timeIntervalSince1970 ?? 0)"
            )
            NotificationCenter.default.post(name: NSNotification.Name("ViewDidAppear"), object: nil)
            ThreadListViewModel.shared.markThreadAsRead(thread)
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: NSNotification.Name("ViewDidDisappear"), object: nil)
        }
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
    let showSenderName: Bool
    @State private var messageHeight: CGFloat = 0

    private func processMessageText(_ text: String) -> String {
        return text.replacingOccurrences(
            of: "@\\[assistant\\]", with: "**@[assistant]**", options: .regularExpression)
    }

    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if showSenderName {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Text(.init(processMessageText(message.text)))
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
