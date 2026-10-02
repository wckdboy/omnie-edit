import OmnieEditCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $model.settings.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(title(theme)).tag(theme)
                    }
                }
                Stepper(value: $model.settings.fontSize, in: EditorSettings.minFontSize...EditorSettings.maxFontSize, step: 1) {
                    Text("Font size \(Int(model.settings.fontSize))")
                }
                Toggle("Monospace", isOn: $model.settings.useMonospace)
                Toggle("Line numbers", isOn: $model.settings.showLineNumbers)
                Toggle("Soft wrap", isOn: $model.settings.softWrap)
            } header: {
                Text("Editor")
            }

            Section {
                Picker("Default extension", selection: $model.settings.defaultExtension) {
                    ForEach(SuggestedExtensions.all, id: \.self) { ext in
                        Text(ext).tag(ext)
                    }
                }
            } header: {
                Text("Files")
            } footer: {
                Text(model.storageSummary)
            }

            Section {
                Toggle("Unlock with Face ID or passcode", isOn: lockBinding)
                Toggle("Include in device backup", isOn: $model.settings.includeInDeviceBackup)
            } header: {
                Text("Security")
            } footer: {
                Text("Files use iOS Data Protection and stay unreadable while this iPhone is locked. A locked file is kept out of the shared folder, so omnie-ios cannot read it until you unlock it. Omnie-edit does not send files or analytics over the network.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Text("Omnie-edit \(version)")
                .font(.footnote)
                .foregroundStyle(palette.secondary.color)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { model.settings.appLockEnabled },
            set: { enabled in
                Task { await model.setAppLockEnabled(enabled) }
            }
        )
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func title(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .monochrome:
            return "Monochrome"
        }
    }
}
