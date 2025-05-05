import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct ThreadSettingsForm: View {
    @Binding var threadName: String
    @Binding var apiKey: String
    @Binding var assistantName: String
    @Binding var customInstructions: String
    let showDangerZone: Bool
    let showParticipantsAndAssistant: Bool
    let autoFocusThreadName: Bool
    let onClearAPIKey: () -> Void
    let onSave: () -> Void
    let onDeleteThread: () -> Void
    let isSaving: Bool
    let isSaveDisabled: Bool
    @StateObject private var viewModel: SettingsViewModel
    @State private var isDeleting = false
    @State private var showingAddParticipant = false
    @State private var availableUsers: [User] = []
    @State private var isLoadingAvailableUsers = false
    @FocusState private var isThreadNameFocused: Bool
    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    @State private var showingAssistantSettings = false

    init(
        threadName: Binding<String>,
        apiKey: Binding<String>,
        assistantName: Binding<String>,
        customInstructions: Binding<String>,
        showDangerZone: Bool,
        showParticipantsAndAssistant: Bool = true,
        autoFocusThreadName: Bool = false,
        onClearAPIKey: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onDeleteThread: @escaping () -> Void,
        isSaving: Bool,
        isSaveDisabled: Bool,
        chatId: String
    ) {
        self._threadName = threadName
        self._apiKey = apiKey
        self._assistantName = assistantName
        self._customInstructions = customInstructions
        self.showDangerZone = showDangerZone
        self.showParticipantsAndAssistant = showParticipantsAndAssistant
        self.autoFocusThreadName = autoFocusThreadName
        self.onClearAPIKey = onClearAPIKey
        self.onSave = onSave
        self.onDeleteThread = onDeleteThread
        self.isSaving = isSaving
        self.isSaveDisabled = isSaveDisabled
        self._viewModel = StateObject(wrappedValue: SettingsViewModel(chatId: chatId))
    }

    var body: some View {
        Form {
            Section {
                TextField("Thread Name", text: $threadName)
                    .textInputAutocapitalization(.words)
                    .focused($isThreadNameFocused)
            } header: {
                Text("THREAD NAME")
            }

            Section {
                ZStack {
                    SecureField("OpenAI API Key", text: $apiKey)
                        .padding(.trailing, 32)
                    if !apiKey.isEmpty {
                        HStack {
                            Spacer()
                            Button(action: { apiKey = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        showingAssistantSettings = true
                    } label: {
                        Text("Customize Assistant")
                    }
                    .sheet(isPresented: $showingAssistantSettings) {
                        AssistantSettingsView(viewModel: viewModel)
                    }
                }
            } header: {
                Text("ASSISTANT")
            } footer: {
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 4) {
                        Text("Get your OPEN AI key")
                            .font(.footnote)
                            .fontWeight(.regular)
                        Link(
                            "here",
                            destination: URL(string: "https://platform.openai.com/api-keys")!
                        )
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundColor(.blue)
                    }
                }
            }

            if showParticipantsAndAssistant {
                Section {
                    NavigationLink(destination: ParticipantsView(viewModel: viewModel)) {
                        Text("Participants")
                    }
                }
            }

            if showDangerZone {
                Section {
                    Button(role: .destructive) {
                        // Handle clear conversation
                    } label: {
                        HStack {
                            Text("Clear Conversation")
                            if false {  // Add state for clearing
                                Spacer()
                                ProgressView()
                            }
                        }
                    }

                    Button(role: .destructive) {
                        isDeleting = true
                        onDeleteThread()
                    } label: {
                        HStack {
                            Text("Delete Thread")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                } header: {
                    Text("DANGER ZONE")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Save", action: onSave)
                        .disabled(isSaveDisabled)
                }
            }
        }
        .onAppear {
            if autoFocusThreadName {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isThreadNameFocused = true
                }
            }
        }
    }

    private func loadAvailableUsers() {
        guard let currentUserId = currentUserId else { return }
        isLoadingAvailableUsers = true
        let db = Firestore.firestore()
        db.collection("users").getDocuments { snapshot, error in
            isLoadingAvailableUsers = false
            guard let documents = snapshot?.documents else { return }
            let allUsers = documents.compactMap { try? $0.data(as: User.self) }
            let participantIds = Set(viewModel.participants.map { $0.userId })
            availableUsers = allUsers.filter { user in
                user.userId != currentUserId && !participantIds.contains(user.userId)
            }
        }
    }
}
