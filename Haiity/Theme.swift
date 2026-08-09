import SwiftUI
import UIKit

/// GitHub-Palette, hell + dunkel. Eine Quelle für App und Widget.
enum Theme {
    // MARK: – Contribution-Level

    /// Dunkel-Rampe. `l0` ist bewusst HELLER als eine Karte
    /// (`secondarySystemGroupedBackground` = #1C1C1E) — GitHubs Original
    /// #161b22 hat gegen die Karte nur 1,02:1 Kontrast und verschwindet
    /// dort komplett. #262c36 liegt zwischen Karte und l1, die Rampe
    /// bleibt monoton.
    static let levelsDark: [Color] = [
        Color(red: 0.15, green: 0.17, blue: 0.21),   // l0 #262c36
        Color(red: 0.05, green: 0.27, blue: 0.16),   // l1 #0e4429
        Color(red: 0.00, green: 0.43, blue: 0.20),   // l2 #006d32
        Color(red: 0.15, green: 0.65, blue: 0.25),   // l3 #26a641
        Color(red: 0.22, green: 0.83, blue: 0.33),   // l4 #39d353
    ]
    static let levelsLight: [Color] = [
        Color(red: 0.94, green: 0.95, blue: 0.96),   // #eff2f5
        Color(red: 0.61, green: 0.91, blue: 0.66),   // #9be9a8
        Color(red: 0.25, green: 0.77, blue: 0.39),   // #40c463
        Color(red: 0.19, green: 0.63, blue: 0.31),   // #30a14e
        Color(red: 0.13, green: 0.43, blue: 0.22),   // #216e39
    ]

    static func level(_ n: Int, dark: Bool) -> Color {
        let arr = dark ? levelsDark : levelsLight
        return arr[max(0, min(4, n))]
    }

    // MARK: – Akzent
    //
    // Drei Rollen, weil EINE Grünstufe nicht überall lesbar ist:
    //   accent      – Markenfarbe für FLÄCHEN ohne Text (Glas-Tint,
    //                 Monatsbalken, Chip-Hintergründe).
    //   accentFill  – gefüllte Pillen MIT weißer Schrift; dunkel genug für
    //                 ≥ 4,5:1 gegen Weiß (vorher 3,37:1).
    //   accentText  – Akzent als SCHRIFT/Symbol auf Systemhintergrund;
    //                 hell im Dark Mode, dunkel im Light Mode.

    static let accent = Color(red: 0.18, green: 0.63, blue: 0.26) // #2ea043

    /// #1f883d (hell) / #238636 (dunkel) — Weiß darauf: 4,52:1 / 4,63:1.
    static let accentFill = dynamic(light: 0x1F883D, dark: 0x238636)

    /// #1a7f37 (hell, 5,08:1 auf Weiß) / #3fb950 (dunkel, 6,7:1 auf #1C1C1E).
    static let accentText = dynamic(light: 0x1A7F37, dark: 0x3FB950)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        let l = uiColor(light), d = uiColor(dark)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    enum Haptics {
        static func check() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}
