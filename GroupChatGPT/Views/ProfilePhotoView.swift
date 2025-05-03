import SwiftUI

struct ProfilePhotoView: View {
    let image: Image?
    let name: String
    let size: CGFloat
    let placeholderColor: String?

    private var initial: String {
        name.prefix(1).uppercased()
    }

    private var backgroundColor: Color {
        if let colorName = placeholderColor {
            switch colorName {
            case "red": return .red
            case "orange": return .orange
            case "yellow": return .yellow
            case "green": return .green
            case "blue": return .blue
            case "purple": return .purple
            case "pink": return .pink
            case "indigo": return .indigo
            default: return .gray
            }
        }
        return .gray
    }

    var body: some View {
        Group {
            if let image = image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: size, height: size)

                    Text(initial)
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProfilePhotoView(image: nil, name: "John Doe", size: 40, placeholderColor: "blue")
        ProfilePhotoView(image: nil, name: "Alice Smith", size: 60, placeholderColor: "green")
        ProfilePhotoView(image: nil, name: "Bob Johnson", size: 80, placeholderColor: "red")
    }
    .padding()
}
