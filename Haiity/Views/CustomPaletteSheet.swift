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
            // Same continuous surface as every other More sub-page, not a stock
            // `Form`: iOS 27 drops taps on grouped list rows, and this sheet is
            // all tap targets.
            ScrollView {
                VStack(spacing: Theme.Metrics.settingsSectionGap) {
                    AppSettingsGroup(title: String(localized: "Grundfarbe")) {
                        HueTileGrid(selected: base) { color = Theme.color($0) }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("custom-palette-tiles")
                        groupDivider
                        ColorPicker(selection: $color, supportsOpacity: false) {
                            Label(String(localized: "Feinabstimmung"), systemImage: "eyedropper")
                        }
                        .accessibilityIdentifier("custom-palette-color")
                        Text(String(localized: "hAiity erzeugt daraus alle Rasterstufen."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AppSettingsGroup(title: String(localized: "Vorschau")) {
                        preview(String(localized: "Hell"), dark: false)
                        groupDivider
                        preview(String(localized: "Dunkel"), dark: true)
                    }

                    AppSettingsGroup(title: String(localized: "Name")) {
                        TextField(String(localized: "Name (z. B. Petrol)"), text: $name)
                            .accessibilityIdentifier("custom-palette-name")
                    }
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.bottom, ChromeLayout.nativeTabBarClearance)
            }
            .scrollIndicators(.hidden)
            .softScrollEdges()
            .settingsChrome()
            .appPageHeader(existing == nil
                           ? String(localized: "Eigene Farbe")
                           : String(localized: "Farbe bearbeiten"))
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

    /// Inset to the text edge, matching the other settings groups.
    private var groupDivider: some View {
        Divider().padding(.leading, Theme.Metrics.gap)
    }

    /// Eine Vorschauzeile: Beschriftung plus das Markenmotiv als ECHTES
    /// Mini-Raster auf seiner Karte — man sieht das Jahresraster, nicht
    /// eine abstrakte Stufenreihe. Das Schema kommt als erzwungene Umgebung,
    /// damit beide Zeilen unabhängig vom gerade aktiven Schema stimmen.
    private func preview(_ title: String, dark: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            MotifGrid(pattern: MotifGrid.brand, palette: style, cellSize: 10)
                .environment(\.colorScheme, dark ? .dark : .light)
                .padding(8)
                .background(Theme.color(PaletteGenerator.cardHex(dark: dark)),
                            in: RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
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
