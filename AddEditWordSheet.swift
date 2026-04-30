import SwiftUI
import SwiftData

struct AddEditWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let word: Word?

    @State private var text = ""
    @State private var definition = ""
    @State private var example = ""

    private var isEditing: Bool { word != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Enter word", text: $text)
                }
                Section("Definition") {
                    TextField("Enter definition", text: $definition, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Example (Optional)") {
                    TextField("Example sentence", text: $example, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Edit Word" : "Add Word")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty ||
                              definition.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let word {
                    text = word.text
                    definition = word.definition
                    example = word.example
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDef = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExample = example.trimmingCharacters(in: .whitespacesAndNewlines)

        if let word {
            word.text = trimmedText
            word.definition = trimmedDef
            word.example = trimmedExample
        } else {
            modelContext.insert(Word(
                text: trimmedText,
                definition: trimmedDef,
                example: trimmedExample
            ))
        }
    }
}
