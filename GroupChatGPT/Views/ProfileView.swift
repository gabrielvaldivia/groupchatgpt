import PhotosUI
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack {
                        PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                            Group {
                                if let image = viewModel.profileImage {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 120, height: 120)
                                        .foregroundStyle(.gray)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical)

                    TextField("Name", text: $viewModel.name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task {
                            if viewModel.isEdited {
                                await viewModel.saveChanges()
                            }
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .task {
                await viewModel.loadProfile()
            }
        }
    }
}
