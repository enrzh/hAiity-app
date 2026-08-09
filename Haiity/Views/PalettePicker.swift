import SwiftUI

/// Farbwahl als Rampen-Chips statt als Menü: eine Palette erkennt man an
/// ihren vier Stufen, nicht an ihrem Namen. Jeder Chip zeigt genau das, was
/// später im Raster steht (l1…l4 im aktuellen Schema).
///
/// Zwei Rollen, ein Bauteil:
///  * global (`allowsGlobal == false`) — sechs Paletten, eine ist immer aktiv.
///  * pro Habit (`allowsGlobal == true`) — davor der Chip „Wie App", der die
///    Übersteuerung wieder abräumt.
struct PalettePicker: View {
    @Binding var selection: GraphPalette?
    /// true = „Wie App" ist erlaubt (nil-Auswahl), also die Habit-Variante.
    var allowsGlobal: Bool = false
    /// Welche Palette „Wie App" gerade bedeutet — der Chip zeigt sie an.
    var globalPalette: GraphPalette = .default

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if allowsGlobal {
                    chip(palette: globalPalette,
                         title: String(localized: "Wie App"),
                         selected: selection == nil) { selection = nil }
                        .accessibilityIdentifier("palette-global")
                }
                ForEach(GraphPalette.allCases) { palette in
                    chip(palette: palette,
                         title: palette.displayName,
                         selected: selection == palette) { selection = palette }
                        .accessibilityIdentifier("palette-\(palette.rawValue)")
                }
            }
            .padding(.vertical, 4)
            // Ein Chip an der Kante darf nicht angeschnitten wirken.
            .padding(.horizontal, 1)
        }
        .accessibilityIdentifier("palette-picker")
    }

    private func chip(palette: GraphPalette,
                      title: String,
                      selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(1..<5) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.level(level, dark: scheme == .dark, palette: palette))
                            .frame(width: 10, height: 10)
                    }
                }
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
                    .strokeBorder(selected ? Theme.accentText(palette) : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
