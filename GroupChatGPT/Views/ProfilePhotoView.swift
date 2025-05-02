import SwiftUI

struct ProfilePhotoView: View {
    let image: Image?
    let name: String
    let size: CGFloat

    private var initial: String {
        name.prefix(1).uppercased()
    }

    private var randomColor: Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .blue, .purple, .pink, .indigo,
        ]
        return colors.randomElement() ?? .gray
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
                        .fill(randomColor)
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
        ProfilePhotoView(image: nil, name: "John Doe", size: 40)
        ProfilePhotoView(image: nil, name: "Alice Smith", size: 60)
        ProfilePhotoView(image: nil, name: "Bob Johnson", size: 80)
    }
    .padding()
}
