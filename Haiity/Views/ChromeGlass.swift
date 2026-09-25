import SwiftUI

// Shared chrome glass. It used to live privately inside ContentView, which meant
// the speak-to-create sheet had no way to reach the same material logic — the
// preferences, the performance mode, and the solid/milky/liquid/adaptive
// decision all lived in one file. A second implementation would have drifted
// from it the first time a material preference changed.
//
// The rule this component encodes, from Liquid Glass: the material belongs to the
// floating functional layer. It is for controls that sit ABOVE content — never for
// a card, a row, or a panel of text. Callers get one glass surface each, inside a
// GlassEffectContainer, so two of them merge into one shape instead of stacking
// into mush.

/// Ein Stück Chrom-Glas. Ab iOS 26 ECHTES Liquid Glass (`glassEffect`,
/// interaktiv, im `GlassEffectContainer` mit stabiler `glassEffectID`, damit
/// Formen ineinander morphen können statt zu blenden); darunter die
/// Material-Attrappe, die es dort schon immer war.
struct ChromeGlass: ViewModifier {
    enum Kind { case capsule, circle }

    let id: String
    let namespace: Namespace.ID
    let kind: Kind
    /// nil = neutrales Glas (Umschalter); gesetzt = eingefärbt (Anlegen).
    var accent: PaletteStyle?
    /// Teilen zwei Teile dieselbe Vereinigungs-Kennung, rechnet iOS ihr Glas
    /// als EINE Form — kein Steg, keine Taille, kein „halb drin, halb
    /// draußen". Verschiedene Kennungen = zwei getrennte Scheiben.
    var union: String
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if appearancePreferences.performanceMode {
            solid(content)
        } else {
            switch Theme.effectiveMaterial(appearancePreferences) {
            case .solid:
                solid(content)
            case .milky:
                material(content)
            case .liquid:
                if #available(iOS 26, *) {
                    glass(content)
                } else {
                    material(content)
                }
            case .adaptive:
                if #available(iOS 26, *) {
                    glass(content)
                } else {
                    material(content)
                }
            }
        }
    }

    @ViewBuilder
    private func solid(_ content: Content) -> some View {
        switch kind {
        case .capsule:
            content
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        case .circle:
            content
                .background(accent.map(Theme.accentFill)
                            ?? Color(.secondarySystemGroupedBackground), in: Circle())
        }
    }

    /// `.regular` (nie `.clear`) — das ist die Variante für Bedienelemente
    /// über beliebigem, scrollendem Inhalt. Für den neutralen Umschalter
    /// reicht sie über einem dicht gefüllten Raster trotzdem nicht: die
    /// Symbole standen im Habit-Text dahinter. Deshalb liegt ein
    /// SYSTEMHINTERGRUND mit halber Deckung als Tint darin — die kleinste
    /// Dosis, die alle drei Zeichen über einer voll gefüllten dunklen Karte
    /// lesbar macht, ohne dass das Glas zu Milchglas wird.
    @available(iOS 26, *)
    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        let style = Glass.regular.tint(glassTint).interactive()
        switch kind {
        case .capsule:
            content.glassEffect(style, in: .capsule)
                .glassEffectID(id, in: namespace)
                .glassEffectUnion(id: union, namespace: namespace)
        case .circle:
            content.glassEffect(style, in: .circle)
                .glassEffectID(id, in: namespace)
                .glassEffectUnion(id: union, namespace: namespace)
        }
    }

    private var glassTint: Color {
        if let accent {
            return Theme.accent(accent)
        } else if Theme.effectiveMaterial(appearancePreferences) == .adaptive {
            return Theme.color(Theme.adaptiveTintHex(preferences: appearancePreferences,
                                                     dark: colorScheme == .dark))
                .opacity(Theme.adaptiveSurfaceOpacity(preferences: appearancePreferences,
                                                       dark: colorScheme == .dark))
        } else {
            return Color(.systemBackground).opacity(
                Theme.surfaceTintOpacity(preferences: appearancePreferences,
                                         dark: colorScheme == .dark))
        }
    }

    /// Unter iOS 26 gibt es kein Glas, das ineinanderfließen könnte. Der
    /// `matchedGeometryEffect` besorgt wenigstens die Bewegung: der Knopf
    /// FÄHRT in die Leiste und verschwindet dort, statt in der Ecke
    /// auszublenden und links wieder aufzublitzen.
    @ViewBuilder
    private func material(_ content: Content) -> some View {
        switch kind {
        case .capsule:
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                .matchedGeometryEffect(id: id, in: namespace)
        case .circle:
            content
                .background(accent.map { Theme.accentFill($0) }
                            ?? Color(.secondarySystemGroupedBackground), in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .matchedGeometryEffect(id: id, in: namespace)
        }
    }
}
