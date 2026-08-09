import SwiftUI
import UIKit

/// GitHub-Palette, hell + dunkel. Eine Quelle für App und Widget.
enum Theme {
    static let levelsDark: [Color] = [
        Color(red: 0.09, green: 0.11, blue: 0.13),   // l0 #161b22
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

    static let accent = Color(red: 0.18, green: 0.63, blue: 0.26) // #2ea043

    enum Haptics {
        static func check() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}
