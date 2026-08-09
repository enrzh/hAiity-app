import SwiftUI

@main
struct HaiityApp: App {
    var body: some Scene {
        WindowGroup {
            // Schema, Palette und Tint setzt ContentView selbst — dort liegt
            // der Store, der sie hält.
            ContentView()
        }
    }
}
