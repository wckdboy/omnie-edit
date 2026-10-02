import OmnieDocumentKit
import OmnieEditCore
import SwiftUI

struct NewDocumentSheet: View {
    @Bindable var model: AppModel
    var onCreate: (LibraryDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var name = ""
    @State private var ext: String
    @State private var errorText: String?

    init(model: AppModel, onCreate: @escaping (LibraryDocument) -> Void) {
        self.model = model
        self.onCreate = onCreate
        _ext = State(initialValue: model.settings.defaultExtension)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Extension", selection: $ext) {
                    ForEach(SuggestedExtensions.all, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(palette.secondary.color)
                }
            }
            .navigationTitle("New file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        let resolved = resolvedName()
        guard !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Name the file."
            return
        }
        model.settings.defaultExtension = ext
        guard let document = model.create(name: resolved) else {
            errorText = model.lastError ?? "Could not create the file."
            return
        }
        onCreate(document)
        dismiss()
    }

    private func resolvedName() -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let parts = OmnieFileName.splittingExtension(trimmed)
        if parts.ext.isEmpty {
            return OmnieFileName.joining(base: trimmed, ext: ext)
        }
        return trimmed
    }
}
