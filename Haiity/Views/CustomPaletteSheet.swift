import SwiftUI

/// Anlegen und Bearbeiten einer eigenen Farbe.
///
/// Der Nutzer wählt EINE Farbe; die fünf Stufen rechnet die App daraus (siehe
/// `PaletteGenerator`). Deshalb steht die Vorschau hier auch nicht als
/// Dekoration daneben, sondern ist der eigentliche Inhalt des Blattes: sie
/// zeigt beide Schemata gleichzeitig und in Rastermaßen, damit man vor dem
/// Sichern sieht, was das Jahresraster daraus macht — auch das, was man gerade
/// nicht eingeschaltet hat.
struct CustomPaletteSheet: View {
    let store: HabitStore
    /// nil = neu anlegen.
    var existing: CustomPalette?

    @Environment(\.dismiss) private var dismiss

    @State private var color: Color = Theme.color(0x0F766E)
    @State private var name = ""
    /// Erst nach dem ersten Erscheinen füllen — `onAppear` überschreibt sonst
    /// bei jedem Neuzeichnen die Eingaben.
    @State private var loaded = false

    private var base: UInt32 { Theme.hex(from: color) }
    private var style: PaletteStyle { PaletteGenerator.style(base: base) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker(selection: $color, supportsOpacity: false) {
                        Label(String(localized: "Grundfarbe"), systemImage: "eyedropper")
                    }
                    .accessibilityIdentifier("custom-palette-color")
                } footer: {
                    Text(String(localized: "Eine Farbe genügt — die fünf Stufen des Rasters rechnet hAiity daraus."))
                }

                Section {
                    preview(String(localized: "Hell"), dark: false)
                    preview(String(localized: "Dunkel"), dark: true)
                } header: {
                    Text(String(localized: "Vorschau"))
                }

                Section {
                    TextField(String(localized: "Name (z. B. Petrol)"), text: $name)
                        .accessibilityIdentifier("custom-palette-name")
                }
            }
            .navigationTitle(existing == nil
                             ? String(localized: "Eigene Farbe")
                             : String(localized: "Farbe bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen")) { dismiss() }
                        .accessibilityIdentifier("custom-palette-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern")) { save() }
                        .accessibilityIdentifier("custom-palette-save")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                color = Theme.color(existing.base)
                name = existing.name
            }
        }
    }

    /// Eine Vorschauzeile: Beschriftung plus die fünf ECHTEN Rasterzellen.
    /// `RampSwatch` bekommt das Schema als Wert (nicht aus der Umgebung),
    /// sonst könnte hier nur das gerade eingestellte gezeigt werden.
    private func preview(_ title: String, dark: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            RampSwatch(style: style, dark: dark)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier(dark ? "custom-palette-preview-dark" : "custom-palette-preview-light")
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var palette = existing {
            palette.name = trimmed
            palette.base = base
            store.updateCustomPalette(palette)
        } else {
            store.addCustomPalette(name: trimmed, base: base)
        }
        Theme.Haptics.success()
        dismiss()
    }
}
