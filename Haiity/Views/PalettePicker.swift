import SwiftUI

/// Farbwahl als Rampen-Chips statt als Menü: eine Palette erkennt man an
/// ihren Stufen, nicht an ihrem Namen. Jeder Chip zeigt GENAU das, was später
/// im Raster steht — dieselbe Zelle (`GridCell`), dieselbe Kantenlänge,
/// derselbe Eckradius, derselbe Abstand, dieselbe Reihenfolge l0…l4.
///
/// Zwei Rollen, ein Bauteil:
///  * global (`allowsGlobal == false`) — die eingebauten Familien plus die
///    eigenen Farben, eine ist immer aktiv.
///  * pro Habit (`allowsGlobal == true`) — davor der Chip „Wie App", der die
///    Übersteuerung wieder abräumt.
struct PalettePicker: View {
    @Binding var selection: PaletteRef?
    /// true = „Wie App" ist erlaubt (nil-Auswahl), also die Habit-Variante.
    var allowsGlobal: Bool = false
    /// Die globale Farbe UND die eigenen Paletten — der Chip „Wie App" zeigt
    /// die globale an, die eigenen stehen hinter den eingebauten.
    var palettes: PaletteBook = PaletteBook()

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if allowsGlobal {
                    chip(style: palettes.style,
                         title: String(localized: "Wie App"),
                         selected: selection == nil) { selection = nil }
                        .accessibilityIdentifier("palette-global")
                }
                ForEach(GraphPalette.allCases) { palette in
                    chip(style: palette.style,
                         title: palette.displayName,
                         selected: selection == .builtin(palette)) { selection = .builtin(palette) }
                        .accessibilityIdentifier("palette-\(palette.rawValue)")
                }
                ForEach(palettes.customs) { custom in
                    chip(style: custom.style,
                         title: custom.displayName,
                         selected: selection == .custom(custom.id)) { selection = .custom(custom.id) }
                        .accessibilityIdentifier("palette-custom-\(custom.id.uuidString)")
                }
            }
            .padding(.vertical, 4)
            // Ein Chip an der Kante darf nicht angeschnitten wirken.
            .padding(.horizontal, 1)
        }
        // Ohne .contain schluckt der Container seine Kinder: die Chips
        // palette-global / palette-<name> / palette-custom-<uuid> wären im
        // AX-Baum unauffindbar. Auf HabitCard und ArchiveView jeweils mit
        // einem Kontrolllauf nachgewiesen (ohne die Zeile: 0 Treffer).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("palette-picker")
    }

    private func chip(style: PaletteStyle,
                      title: String,
                      selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RampSwatch(style: style, dark: scheme == .dark, size: 10)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.accentText(style) : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: – Zeilenform (Liste in „Mehr")

/// Eine Palette als LISTENZEILE: links die fünf Rasterquadrate, daneben der
/// Name, rechts der Haken. Dasselbe Bauteil für eingebaute und eigene Farben —
/// der Unterschied ist nur, was daneben passieren darf (umbenennen, löschen).
struct PaletteRow: View {
    let style: PaletteStyle
    let title: String
    let selected: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RampSwatch(style: style, dark: scheme == .dark)
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText(style))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
