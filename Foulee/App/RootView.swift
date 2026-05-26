import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Foulée")
                .font(.system(size: 40, weight: .heavy))
            Text("Bouge un peu, chaque midi.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
