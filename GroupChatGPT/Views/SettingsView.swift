import SwiftUI

struct SettingsView: View {
    let chatId: String
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var isClearing = false
    @State private var showInvalidKeyAlert = false
    @State private var showEmptyNameAlert = false

    init(chatId: String) {
        self.chatId = chatId
        self._viewModel = StateObject(wrappedValue: SettingsViewModel(chatId: chatId))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Thread Name", text: $viewModel.threadName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("THREAD INFO")
                }

                Section {
                    TextField("Enter API Key", text: $viewModel.apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textCase(.none)
                        .monospaced()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .textContentType(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            validateAndSaveKey()
                        }

                    if !viewModel.apiKey.isEmpty {
                        Button(role: .destructive, action: viewModel.clearAPIKey) {
                            Text("Clear API Key")
                        }
                    }
                } header: {
                    Text("OPENAI API KEY")
                } footer: {
                    Text("This API key will be shared with all participants in this chat.")
                }

                Section {
                    Link(
                        "Get API Key",
                        destination: URL(string: "https://platform.openai.com/api-keys")!)
                }

                Section {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        HStack {
                            Text("Clear Conversation")
                            if isClearing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearing)
                } footer: {
                    Text("This will permanently delete all messages in the conversation.")
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Text("Delete Thread")
                            if viewModel.isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isDeleting)
                } footer: {
                    Text(
                        "This will permanently delete this thread and all its messages. This action cannot be undone."
                    )
                }
            }
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Done") {
                            saveChanges()
                        }
                    }
                }
            }
            .alert("Invalid API Key", isPresented: $showInvalidKeyAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid OpenAI API key starting with 'sk-'")
            }
            .alert("Clear Conversation", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        isClearing = true
                        await viewModel.clearAllMessages()
                        isClearing = false
                    }
                }
            } message: {
                Text("Are you sure you want to clear all messages? This action cannot be undone.")
            }
            .alert("Delete Thread", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await viewModel.deleteThread()
                            dismiss()
                        } catch {
                            print("Error deleting thread: \(error)")
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this thread? This action cannot be undone.")
            }
            .alert("Invalid Thread Name", isPresented: $showEmptyNameAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid thread name")
            }
        }
    }

    private func validateAndSaveKey() {
        let key = viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || (key.starts(with: "sk-") && key.count > 20) {
            viewModel.updateAPIKey(key)
        } else {
            showInvalidKeyAlert = true
        }
    }

    private func saveChanges() {
        let trimmedName = viewModel.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            showEmptyNameAlert = true
            return
        }

        Task {
            do {
                try await viewModel.updateThread(name: viewModel.threadName)
                validateAndSaveKey()
                dismiss()
            } catch {
                print("Error updating thread: \(error)")
            }
        }
    }
}
