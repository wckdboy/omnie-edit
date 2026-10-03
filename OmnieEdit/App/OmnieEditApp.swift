import SwiftUI

@main
struct OmnieEditApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DocumentListView(model: model)
                .preferredColorScheme(preferredScheme)
                .onChange(of: scenePhase) { _, phase in
                    model.handle(scenePhase: phase)
                }
                .onOpenURL { url in
                    _ = model.openPickedFile(url)
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
