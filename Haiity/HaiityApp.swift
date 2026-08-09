import SwiftUI

@main
struct HaiityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // accentText statt accent: die Markenfarbe #2ea043 hat auf
                // hellem Grund nur 3,37:1 — als Schrift/Symbolfarbe (Buttons,
                // Tab-Auswahl, Links) ist das zu wenig.
                .tint(Theme.accentText)
        }
    }
}
