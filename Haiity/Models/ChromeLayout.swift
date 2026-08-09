import CoreGraphics

/// Die Geometrie der schwebenden Leiste unten — als PURE Rechnung, ohne
/// SwiftUI. Zwei Dinge stehen hier, weil sie in der Ansicht nicht prüfbar
/// wären und beide schon einmal falsch waren:
///
///  * **Wohin der Anlegen-Knopf fährt.** Er ist EIN Knopf mit EINER
///    Identität, der beim Zusammenziehen an die Kapsel WANDERT (siehe
///    ContentView.chromeStack). Dafür braucht es beide Zielpositionen als
///    Zahl — eine, die sich zwischen ihnen interpolieren lässt. Vorher gab
///    es zwei verschiedene Knöpfe in zwei Zweigen; SwiftUI blendet so etwas
///    über, und genau das war die Rückmeldung („not do the fade thing").
///  * **Welches Segment der Finger gerade trifft.** Der Umschalter folgt
///    einem gedrückten Finger über die Segmente (wie die System-Tableiste),
///    und das Treffer-Verfahren muss auch dann eine Antwort geben, wenn der
///    Finger etwas über oder unter der Kapsel wandert.
enum ChromeLayout {
    /// Der eine Rand, aus dem beide Kapselradien folgen: (52 − 44)/2 = 4.
    /// Er ist auch der Abstand ZWISCHEN den beiden Lasuren.
    static let inset: CGFloat = (Theme.Metrics.control - Theme.Metrics.hit) / 2

    /// Breite der Kapsel im ZUSAMMENGEZOGENEN Zustand — gerechnet, nicht
    /// gemessen. Zusammengezogen tragen die beiden Ziele keine Beschriftung
    /// mehr, jedes ist also genau `hit` breit (das Symbolkästchen mit 32 pt
    /// ist schmaler und verliert gegen die Mindestbreite):
    ///
    ///     2 × hit          die beiden Lasuren            88
    ///   + 1 × inset        Abstand dazwischen             4
    ///   + 2 × inset        Rand links und rechts          8
    ///   ------------------------------------------------ 100
    ///
    /// Gerechnet statt per GeometryReader gemessen, weil eine Messung
    /// während der Animation als ungetakteter Zustandswechsel zurückkommt:
    /// der Knopf würde dem Blob dann eine Bildwiederholung hinterherhinken
    /// und ruckeln. Dynamic Type ändert an der Zahl nichts — im
    /// zusammengezogenen Zustand steht dort kein Text.
    static let collapsedSwitcherWidth: CGFloat = 2 * Theme.Metrics.hit + 3 * inset

    /// Linke Kante des Anlegen-Knopfes, gemessen von der linken Kante der
    /// Chrom-Zeile.
    ///
    /// Zusammengezogen überlappt er die Kapsel um `gap` — negativer Abstand
    /// ist hier Absicht: er ist damit näher als der `spacing` des
    /// `GlassEffectContainer`, und erst dann rechnet iOS beide Formen als
    /// EINE Fläche, statt zwei Scheiben nebeneinander zu stellen.
    static func addButtonX(collapsed: Bool, rowWidth: CGFloat) -> CGFloat {
        let merged = collapsedSwitcherWidth - Theme.Metrics.gap
        guard !collapsed else { return merged }
        // Auf absurd schmalen Zeilen (Vorschauen, iPad-Slide-Over) darf der
        // Knopf nicht LINKS von seiner Blob-Position landen — sonst führe er
        // beim Zusammenziehen rückwärts.
        return max(merged, rowWidth - Theme.Metrics.control)
    }

    /// Welches Segment liegt unter dem Finger?
    ///
    /// Waagerecht wird auf die nächste Segment-Spanne GEKLEMMT statt strikt
    /// getroffen: wer über den linken Rand hinauszieht, meint weiterhin das
    /// linke Segment. Senkrecht gibt es `slack` Toleranz über und unter der
    /// Kapsel — ein Finger, der beim Ziehen ein paar Punkte nach oben
    /// rutscht, soll die Auswahl nicht abbrechen lassen. Erst ausserhalb
    /// davon ist es ein Abbruch (`nil`), und die Lasur springt zurück.
    static func segment<Key: Hashable>(at point: CGPoint,
                                       frames: [Key: CGRect],
                                       slack: CGFloat = 28) -> Key? {
        guard !frames.isEmpty else { return nil }
        let top = frames.values.map(\.minY).min() ?? 0
        let bottom = frames.values.map(\.maxY).max() ?? 0
        guard point.y > top - slack, point.y < bottom + slack else { return nil }
        // Waagerecht ebenfalls begrenzt: weit neben der Leiste losgelassen
        // heisst abbrechen, nicht „das äusserste Segment".
        let left = frames.values.map(\.minX).min() ?? 0
        let right = frames.values.map(\.maxX).max() ?? 0
        guard point.x > left - slack, point.x < right + slack else { return nil }
        return frames.min { a, b in
            let da = distance(point.x, to: a.value), db = distance(point.x, to: b.value)
            // Gleichstand (der Finger sitzt exakt im Spalt): die linkere
            // Spanne gewinnt, damit die Antwort deterministisch ist.
            return da == db ? a.value.minX < b.value.minX : da < db
        }?.key
    }

    /// Waagerechter Abstand zu einer Spanne — 0, wenn der Punkt darin liegt.
    private static func distance(_ x: CGFloat, to rect: CGRect) -> CGFloat {
        if x < rect.minX { return rect.minX - x }
        if x > rect.maxX { return x - rect.maxX }
        return 0
    }
}
