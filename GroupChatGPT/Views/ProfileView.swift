import PhotosUI
import SwiftUI

@MainActor
struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack {
                        ImagePickerView(
                            selectedItem: $viewModel.selectedItem,
                            displayImage: viewModel.displayImage
                        )
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

struct ImagePickerView: View {
    @Binding var selectedItem: PhotosPickerItem?
    let displayImage: Image?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ProfileImageView(image: displayImage)
        }
    }
}

private struct ProfileImageView: View {
    let image: Image?

    var body: some View {
        Group {
            if let image = image {
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
}
