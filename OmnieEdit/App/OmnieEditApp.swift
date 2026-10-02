import SwiftUI

@main
struct OmnieEditApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(preferredScheme)
                .onChange(of: scenePhase) { _, phase in
                    model.handle(scenePhase: phase)
                }
                .onOpenURL { url in
                    model.importFile(at: url)
                }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch model.settings.theme {
        case .system, .monochrome:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.resolve(model.settings.theme, colorScheme)
        ZStack {
            if model.gate.needsAppUnlock {
                LockScreen(model: model)
            } else {
                DocumentListView(model: model)
                if model.gate.privacyCover {
                    PrivacyShield()
                }
            }
        }
        .environment(\.palette, palette)
        .tint(palette.text)
        .background(palette.background.ignoresSafeArea())
    }
}

extension Notification.Name {
    static let omnieFlushSaves = Notification.Name("omnie.flushSaves")
}
