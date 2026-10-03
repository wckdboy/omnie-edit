import OmnieEditCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var gitName = ""
    @State private var gitEmail = ""

    var body: some View {
        Form {
            Section {
                handSelector
            } header: {
                Text("Preferred Hand")
            } footer: {
                Text("Primary controls move to the selected side of the bottom toolbar.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $model.settings.theme) {
                    Text("System").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                    Text("Monochrome").tag(AppTheme.monochrome)
                }
            }

            Section("Editor") {
                textSizeControl
                Toggle("Line Numbers", isOn: $model.settings.showLineNumbers)
                Toggle("Soft Wrap", isOn: $model.settings.softWrap)
            }

            Section {
                TextField("Name", text: $gitName)
                    .textContentType(.name)
                TextField("Email", text: $gitEmail)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Button("Save Git Identity") {
                    model.saveGitIdentity(name: gitName, email: gitEmail)
                }
                .disabled(
                    gitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || gitEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            } header: {
                Text("Git Identity")
            } footer: {
                Text("Used only to author local commits. Stored in this device’s Keychain.")
            }

            Section {
                Text("Omnie Edit \(version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Files remain in the locations you choose. Omnie Edit does not require an account.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            gitName = model.gitIdentity?.name ?? ""
            gitEmail = model.gitIdentity?.email ?? ""
        }
    }

    private var handSelector: some View {
        Picker("Preferred Hand", selection: preferredHandBinding) {
            Label("Left", systemImage: "hand.point.left.fill").tag(PreferredHand.left)
            Label("Right", systemImage: "hand.point.right.fill").tag(PreferredHand.right)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var preferredHandBinding: Binding<PreferredHand> {
        Binding(
            get: { model.settings.preferredHand },
            set: { model.setPreferredHand($0) }
        )
    }

    private var textSizeControl: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("Text Size")
                Spacer()
                textSizeButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Text Size")
                textSizeButtons
            }
        }
    }

    private var textSizeButtons: some View {
        HStack(spacing: 8) {
            Button {
                model.settings.fontSize -= 1
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Smaller Text")
            .disabled(model.settings.fontSize <= EditorSettings.minFontSize)

            Text("\(Int(model.settings.fontSize)) pt")
                .monospacedDigit()
                .frame(minWidth: 48)

            Button {
                model.settings.fontSize += 1
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Larger Text")
            .disabled(model.settings.fontSize >= EditorSettings.maxFontSize)
        }
    }

    private var version: String {
        let shortVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}
