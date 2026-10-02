import SwiftUI

struct LockScreen: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var attempted = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Omnie-edit")
                .font(.title2.weight(.medium))
                .foregroundStyle(palette.text)
            Text("Files are locked")
                .font(.subheadline)
                .foregroundStyle(palette.secondary)
            Button("Unlock") {
                Task { await model.unlockApp() }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.text)
            .foregroundStyle(palette.background)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background.ignoresSafeArea())
        .task {
            guard !attempted else { return }
            attempted = true
            await model.unlockApp()
        }
    }
}

struct PrivacyShield: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            Text("Omnie-edit")
                .font(.title3.weight(.medium))
                .foregroundStyle(palette.text)
        }
        .accessibilityAddTraits(.isModal)
    }
}
