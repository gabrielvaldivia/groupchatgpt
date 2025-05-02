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
            ThreadSettingsForm(
                threadName: $viewModel.threadName,
                apiKey: $viewModel.apiKey,
                assistantName: $viewModel.assistantName,
                customInstructions: $viewModel.customInstructions,
                showDangerZone: true,
                onClearAPIKey: viewModel.clearAPIKey,
                onSave: saveChanges,
                isSaving: viewModel.isUpdating,
                isSaveDisabled: viewModel.threadName.isEmpty
            )
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
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
                viewModel.updateAssistantName(viewModel.assistantName)
                viewModel.updateCustomInstructions(viewModel.customInstructions)
                dismiss()
            } catch {
                print("Error updating thread: \(error)")
            }
        }
    }
}
