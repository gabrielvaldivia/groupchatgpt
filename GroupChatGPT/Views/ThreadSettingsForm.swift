import SwiftUI

struct ThreadSettingsForm: View {
    @Binding var threadName: String
    @Binding var apiKey: String
    @Binding var assistantName: String
    @Binding var customInstructions: String
    let showDangerZone: Bool
    let onClearAPIKey: () -> Void
    let onSave: () -> Void
    let isSaving: Bool
    let isSaveDisabled: Bool

    var body: some View {
        Form {
            Section {
                TextField("Thread Name", text: $threadName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("THREAD NAME")
            }

            Section {
                TextField("Enter API Key", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textCase(.none)
                    .monospaced()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .textContentType(.none)
                    .disableAutocorrection(true)

                if !apiKey.isEmpty {
                    Button(role: .destructive, action: onClearAPIKey) {
                        Text("Clear API Key")
                    }
                }
            } header: {
                Text("OPENAI API KEY")
            } footer: {
                Text("This API key will be shared with everyone in this chat. You can ")
                    + Text("[get an API key](https://platform.openai.com/api-keys)")
                    .foregroundColor(.blue) + Text(" from OpenAI.")
            }

            Section {
                TextField("Assistant Name", text: $assistantName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("ASSISTANT NAME")
            } footer: {
                Text(
                    "This is the name you'll use to address the AI assistant in chat (e.g. '@Alice' or 'Hey Alice')"
                )
            }

            Section {
                TextEditor(text: $customInstructions)
                    .frame(minHeight: 100)
            } header: {
                Text("CUSTOM INSTRUCTIONS")
            } footer: {
                Text(
                    "Add custom instructions to guide how the AI assistant should behave and respond in this chat."
                )
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
                        // Handle delete thread
                    } label: {
                        HStack {
                            Text("Delete Thread")
                            if false {  // Add state for deleting
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
    }
}
