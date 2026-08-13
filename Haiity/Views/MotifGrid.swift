import SwiftUI

/// Das Markenmotiv als lebendiges Raster: die Kacheln erscheinen beim
/// Aufbau NACHEINANDER (Deckkraft + kleine Skala, fester Versatz je
/// Kachel) — derselbe Auftritt im Leerzustand und auf dem
/// Einrichtungs-Bildschirm.
///
/// Der Versatz ist reine Mathematik (`delay(for:)`), damit Tests ihn
/// prüfen können; mit `reduceMotion` steht alles sofort.
struct MotifGrid: View {
    let pattern: [Int]
    let palette: PaletteStyle
    var cellSize: CGFloat = 14

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    static let columns = 12

    /// 18 ms je Kachel: 48 Kacheln füllen sich in knapp einer Sekunde —
    /// ein Lauf, der sichtbar „einer nach dem anderen" liest, aber nie
    /// die Bedienung aufhält (alles bleibt ab dem ersten Frame tippbar).
    static func delay(for index: Int) -> Double {
        Double(max(0, index)) * 0.018
    }

    /// Das FESTE Motiv des Einrichtungs-Bildschirms (kein `random()`: ein
    /// Muster, das bei jedem Aufbau anders aussieht, wirkt wie ein
    /// Ladefehler, nicht wie ein Motiv).
    static let brand: [Int] = [0, 2, 1, 0, 3, 4, 2, 0, 1, 3, 0, 2,
                               1, 0, 3, 2, 0, 1, 4, 3, 0, 2, 1, 0,
                               2, 3, 0, 1, 4, 0, 2, 1, 3, 0, 4, 2]

    /// Ein einmal gewürfeltes Demo-Muster für den Leerzustand — der
    /// Aufrufer hält es fest (`let` im View-Zustand), damit es während
    /// des Auftritts nicht neu würfelt.
    static func randomPattern(count: Int = 48) -> [Int] {
        (0..<count).map { _ in Bool.random() && Bool.random() ? Int.random(in: 1...4) : 0 }
    }

    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(cellSize), spacing: 3),
                         count: Self.columns)
        LazyVGrid(columns: cols, spacing: 3) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: cellSize * 0.22, style: .continuous)
                    .fill(Theme.level(level, dark: scheme == .dark, palette: palette))
                    .frame(height: cellSize)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .animation(reduceMotion ? nil
                               : .spring(response: 0.32, dampingFraction: 0.72)
                                   .delay(Self.delay(for: index)),
                               value: appeared)
            }
        }
        .frame(width: CGFloat(Self.columns) * (cellSize + 3))
        .accessibilityHidden(true)
        .onAppear { appeared = true }
    }
}
