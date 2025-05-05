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
            MessageListView(
                messages: viewModel.messages,
                isFromCurrentUser: viewModel.isFromCurrentUser,
                participantUsers: viewModel.participantUsers,
                thread: viewModel.thread
            )

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

struct MessageRow: View {
    let index: Int
    let message: Message
    let messages: [Message]
    let isFromCurrentUser: Bool
    let participantUsers: [String: User]
    let thread: Thread
    let threadId: String

    private var showName: Bool {
        index == 0 || messages[index - 1].senderId != message.senderId
    }
    private var topSpacing: CGFloat {
        if index == 0 { return 0 }
        return messages[index - 1].senderId == message.senderId ? 4 : 12
    }
    private var user: User? {
        participantUsers[message.senderId]
    }
    private var isAssistant: Bool {
        message.senderId == "ai"
    }
    private var assistantPhotoURLString: String? {
        isAssistant ? thread.assistantProfileImageURL : nil
    }
    private var isLastInGroup: Bool {
        index == messages.count - 1 || messages[index + 1].senderId != message.senderId
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: topSpacing)
            MessageBubble(
                message: message,
                isFromCurrentUser: isFromCurrentUser,
                showSenderName: showName,
                user: user,
                showProfilePhoto: isLastInGroup,
                assistantPhotoURLString: assistantPhotoURLString,
                threadId: threadId
            )
            .id(message.messageId)
        }
    }
}

struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let showSenderName: Bool
    let user: User?
    let showProfilePhoto: Bool
    let assistantPhotoURLString: String?
    let threadId: String
    @State private var messageHeight: CGFloat = 0
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showingAssistantSettings = false

    private func processMessageText(_ text: String) -> String {
        return text.replacingOccurrences(
            of: "@\\[assistant\\]", with: "**@[assistant]**", options: .regularExpression)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if isFromCurrentUser {
                Spacer()
            }

            if !isFromCurrentUser {
                VStack {
                    Spacer()
                    if showProfilePhoto {
                        if message.senderId == "ai", let urlString = assistantPhotoURLString,
                            !urlString.isEmpty
                        {
                            if urlString.hasPrefix("data:"),
                                let image = loadBase64Image(from: urlString)
                            {
                                ProfilePhotoView(
                                    image: image,
                                    name: message.senderName,
                                    size: 32,
                                    placeholderColor: user?.placeholderColor
                                        ?? authService.getUserColor(for: message.senderId)
                                )
                                .onTapGesture {
                                    showingAssistantSettings = true
                                }
                            } else if let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProfilePhotoView(
                                            image: nil,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            showingAssistantSettings = true
                                        }
                                    case .success(let image):
                                        ProfilePhotoView(
                                            image: image,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            showingAssistantSettings = true
                                        }
                                    case .failure(_):
                                        ProfilePhotoView(
                                            image: nil,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            showingAssistantSettings = true
                                        }
                                    @unknown default:
                                        ProfilePhotoView(
                                            image: nil,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            showingAssistantSettings = true
                                        }
                                    }
                                }
                            } else {
                                ProfilePhotoView(
                                    image: nil,
                                    name: message.senderName,
                                    size: 32,
                                    placeholderColor: user?.placeholderColor
                                        ?? authService.getUserColor(for: message.senderId)
                                )
                                .onTapGesture {
                                    showingAssistantSettings = true
                                }
                            }
                        } else {
                            if let url = user?.profileImageURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProfilePhotoView(
                                            image: nil,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            if message.senderId == "ai" {
                                                showingAssistantSettings = true
                                            }
                                        }
                                    case .success(let image):
                                        ProfilePhotoView(
                                            image: image,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            if message.senderId == "ai" {
                                                showingAssistantSettings = true
                                            }
                                        }
                                    case .failure(_):
                                        ProfilePhotoView(
                                            image: nil,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            if message.senderId == "ai" {
                                                showingAssistantSettings = true
                                            }
                                        }
                                    @unknown default:
                                        ProfilePhotoView(
                                            image: nil,
                                            name: message.senderName,
                                            size: 32,
                                            placeholderColor: user?.placeholderColor
                                                ?? authService.getUserColor(for: message.senderId)
                                        )
                                        .onTapGesture {
                                            if message.senderId == "ai" {
                                                showingAssistantSettings = true
                                            }
                                        }
                                    }
                                }
                            } else {
                                ProfilePhotoView(
                                    image: nil,
                                    name: message.senderName,
                                    size: 32,
                                    placeholderColor: user?.placeholderColor
                                        ?? authService.getUserColor(for: message.senderId)
                                )
                                .onTapGesture {
                                    if message.senderId == "ai" {
                                        showingAssistantSettings = true
                                    }
                                }
                            }
                        }
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }
                .frame(width: 32)
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if showSenderName && !isFromCurrentUser {
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
                    .frame(
                        maxWidth: isFromCurrentUser ? 280 : .infinity,
                        alignment: isFromCurrentUser ? .trailing : .leading)
            }
            .padding(.horizontal, 4)

            if !isFromCurrentUser {
                Spacer()
            }
        }
        .sheet(isPresented: $showingAssistantSettings) {
            AssistantSettingsView(viewModel: SettingsViewModel(chatId: threadId))
        }
    }

    private func loadBase64Image(from dataURL: String) -> Image? {
        guard let base64String = dataURL.components(separatedBy: ",").last,
            let imageData = Data(base64Encoded: base64String),
            let uiImage = UIImage(data: imageData)
        else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
}

struct MessageListView: View {
    let messages: [Message]
    let isFromCurrentUser: (Message) -> Bool
    let participantUsers: [String: User]
    let thread: Thread

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.messageId) {
                        index, message in
                        MessageRow(
                            index: index,
                            message: message,
                            messages: messages,
                            isFromCurrentUser: isFromCurrentUser(message),
                            participantUsers: participantUsers,
                            thread: thread,
                            threadId: thread.threadId
                        )
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { oldCount, newCount in
                if let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.messageId, anchor: .bottom)
                }
            }
        }
    }
}
