import SwiftUI

/// Der pixelige Farbwähler: drei Reihen × zwölf Farbtöne — Quadrate wie im
/// Jahresraster, ein Tipp wählt die Grundfarbe.
///
/// Die Werte sind mit der App-eigenen OKLCH-Mathematik kuratiert (drei
/// Helligkeiten, gleiche Chromatik wie die eingebauten Akzente, Farbtöne
/// alle 30°), damit JEDE Kachel eine gute Rampe ergibt — die mittlere Reihe
/// sind exakt die Basen der zwölf Farbton-App-Icons.
struct HueTileGrid: View {
    let selected: UInt32?
    let onPick: (UInt32) -> Void

    /// hell → mittel → tief; je zwölf Farbtöne alle 30°.
    static let rows: [[UInt32]] = [
        [0xFC699F, 0xFF6F5A, 0xF08700, 0xCCA200, 0x99B400, 0x2DC363,
         0x00C3AB, 0x00BDD5, 0x00AEFF, 0x7B99FF, 0xB484FF, 0xE475DB],
        [0xD2427B, 0xD84836, 0xC06900, 0x9F7E00, 0x789000, 0x009C42,
         0x009984, 0x0096A8, 0x008ACF, 0x5775ED, 0x9360DB, 0xBA4EB4],
        [0x9C0051, 0xA20600, 0x874800, 0x6F5700, 0x516300, 0x006C27,
         0x00695A, 0x006672, 0x006093, 0x3345BA, 0x6930AB, 0x8A1884],
    ]

    private static let toneNames = [String(localized: "hell"),
                                    String(localized: "mittel"),
                                    String(localized: "tief")]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<Self.rows.count, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(Self.rows[row], id: \.self) { hex in
                        tile(hex, tone: Self.toneNames[row])
                    }
                }
            }
        }
    }

    private func tile(_ hex: UInt32, tone: String) -> some View {
        let isSelected = selected == hex
        return Button {
            onPick(hex)
            Theme.Haptics.select()
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.color(hex))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.primary.opacity(isSelected ? 0.9 : 0),
                                      lineWidth: 2)
                )
                .scaleEffect(isSelected ? 1.12 : 1)
                .animation(.snappy(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Farbton \(PaletteGenerator.hueDegrees(hex).map { Int($0.rounded()) } ?? 0)°, \(tone)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
