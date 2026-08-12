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
    static let navigationWidth: CGFloat = 2 * Theme.Metrics.hit + 3 * inset

    /// Linke Kante des Anlegen-Knopfes, gemessen von der linken Kante der
    /// Chrom-Zeile.
    ///
    /// Zusammengezogen überlappt er die Kapsel um `gap` — negativer Abstand
    /// ist hier Absicht: er ist damit näher als der `spacing` des
    /// `GlassEffectContainer`, und erst dann rechnet iOS beide Formen als
    /// EINE Fläche, statt zwei Scheiben nebeneinander zu stellen.
    static func addButtonX(collapsed: Bool, rowWidth: CGFloat) -> CGFloat {
        let merged = navigationWidth - Theme.Metrics.gap
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

/// Die Geometrie der Mehr-Tafel — zwei Zustände, ein Zug, drei mögliche
/// Ausgänge. Wieder als PURE Rechnung, aus demselben Grund wie oben: was in
/// der Ansicht steht, lässt sich nur im Simulator anschauen, und „ab wann
/// klappt sie auf" ist eine Zahl, keine Ansichtssache.
///
/// **Karte oder ganze Seite.** Die Tafel öffnet klein (`ratio`, gedeckelt auf
/// `cap`) — sie soll ein Stück der Habit-Liste stehen lassen, sonst ist sie
/// eine Seite mit anderen Mitteln. Wer mehr will, zieht sie nach oben: dann
/// ist sie die GANZE Seite — von der oberen Sicherheitszone bis an die
/// Unterkante, von Kante zu Kante.
///
/// **Ein Ding, das seine Größe ändert — keine zwei Präsentationen.** Deshalb
/// laufen drei Dinge am selben Fortschritt mit (`progress`, 0 = Karte,
/// 1 = ganze Seite):
///
///  * die HÖHE,
///  * der ECKRADIUS (Kartenradius → Bildschirmradius: eine bildschirmfüllende
///    Fläche mit Kartenecken sieht aus wie ein Fehler),
///  * die SEITENRÄNDER (bis auf 0) und der Überstand nach unten.
///
/// Alles interpoliert, nichts springt: zwischen Karte und Seite gibt es
/// keinen Zustand, in dem eine Kante „umschaltet".
///
/// **Kein Gummiband nach oben mehr.** Früher folgte die Tafel dem Finger über
/// ihre große Höhe hinaus gedämpft weiter. Die große Höhe ist jetzt die obere
/// Sicherheitszone — alles darüber liegt unter Statusleiste und Dynamic
/// Island. Das ist keine Grenze, an der man federn darf, sondern eine, an der
/// man steht.
enum MorePanel {
    /// Anteil der Container-Höhe im kleinen Zustand.
    static let ratio: CGFloat = 0.58
    /// Deckel für den kleinen Zustand (auf großen Geräten sonst zu viel).
    static let cap: CGFloat = 520
    /// Ab hier gilt ein Zug als Entscheidung — nach oben wie nach unten.
    static let snapDistance: CGFloat = 60
    /// Ab hier ist ein Zug nach unten ein Schließen (aus dem kleinen
    /// Zustand); aus dem großen führt er erst zurück auf den kleinen.
    static let dismissDistance: CGFloat = 90
    /// Wie weit der Wurf zählt: ein kurzer, schneller Zug soll dasselbe
    /// bewirken wie ein langer, langsamer.
    static let flickDistance: CGFloat = 180
    /// Eckradius im kleinen Zustand — groß genug, um sich mit einer
    /// 26-pt-Kapsel zu vertragen.
    static let cardRadius: CGFloat = 32

    /// Eckradius, auf den die Tafel bei voller Größe zuläuft.
    ///
    /// Den ECHTEN Wert des Geräts gibt es nicht öffentlich
    /// (`UIScreen._displayCornerRadius` ist privat, und private Schlüssel in
    /// einer eingereichten App sind ein Risiko, das eine Ecke nicht wert
    /// ist). Also eine bewusste Wahl: 52 pt auf Geräten mit gerundetem
    /// Bildschirm (die echten Werte liegen zwischen 47 und 62) — LIEBER ETWAS
    /// ZU ECKIG als zu rund: eine Ecke, die runder ist als die des
    /// Bildschirms, lässt an den unteren Kanten den Hintergrund durchblitzen,
    /// eine eckigere wird von der Bildschirmecke sauber weggeschnitten.
    ///
    /// Ein Gerät ohne Home-Indikator (SE) hat einen RECHTECKIGEN Bildschirm;
    /// dort bleibt es beim Kartenradius, weil es keine Bildschirmecke gibt,
    /// auf die man zulaufen könnte.
    static func screenCornerRadius(safeBottom: CGFloat) -> CGFloat {
        safeBottom > 0 ? 52 : cardRadius
    }

    static func collapsedHeight(container: CGFloat) -> CGFloat {
        max(0, min(container * ratio, cap))
    }

    /// Die GANZE Seite: obere Sicherheitszone bis Bildschirmunterkante.
    ///
    /// Der Container ist die sichere Fläche; die Tafel soll darüber hinaus
    /// noch die untere Sicherheitszone abdecken (sonst endet die Fläche über
    /// dem Home-Indikator und die „ganze Seite" hat einen Streifen).
    static func expandedHeight(container: CGFloat, safeBottom: CGFloat) -> CGFloat {
        // Nie KLEINER als der kleine Zustand: auf einem sehr niedrigen
        // Container (Landscape, Slide-Over) läge der Deckel sonst darunter
        // und die Tafel schrumpfte beim Aufziehen.
        max(collapsedHeight(container: container), container + max(0, safeBottom))
    }

    /// Die Höhe WÄHREND eines Zuges. `drag` ist die Translation des Fingers:
    /// negativ = nach oben, positiv = nach unten.
    ///
    ///  * nach oben: die Tafel WÄCHST bis zur ganzen Seite und dort ist Ende;
    ///  * nach unten aus dem großen Zustand: sie schrumpft bis auf die kleine
    ///    Höhe — und der Zug geht dort WEITER: ab der Kartenhöhe wandert sie
    ///    (siehe `offset`). Vorher stand sie an der Karte fest, und ein
    ///    langsamer Zug vom ganzen Bild zum Rand hielt sichtbar an („it
    ///    stops … and then continues"): der Finger lief, die Tafel nicht.
    ///    Ein Zug ist EIN Weg — ganze Seite → Karte → hinaus, ohne Halt;
    ///  * nach unten aus dem kleinen Zustand: sie behält ihre Höhe und
    ///    WANDERT stattdessen (siehe `offset`) — genau das Verhalten von
    ///    vorher, als es nur eine Höhe gab.
    static func height(container: CGFloat,
                       safeBottom: CGFloat,
                       expanded: Bool,
                       drag: CGFloat) -> CGFloat {
        let small = collapsedHeight(container: container)
        let large = expandedHeight(container: container, safeBottom: safeBottom)
        let base = expanded ? large : small
        if drag < 0 { return min(large, base - drag) }   // drag ist negativ
        guard expanded else { return base }
        return max(small, large - drag)
    }

    // MARK: – Alles, was mit der Höhe mitläuft

    /// 0 = Karte, 1 = ganze Seite. DIE Zahl, an der Radius und Ränder hängen
    /// — damit gibt es genau EINEN Fortschritt und nicht drei, die
    /// auseinanderlaufen können.
    static func progress(container: CGFloat,
                         safeBottom: CGFloat,
                         expanded: Bool,
                         drag: CGFloat) -> CGFloat {
        let small = collapsedHeight(container: container)
        let large = expandedHeight(container: container, safeBottom: safeBottom)
        guard large > small else { return expanded ? 1 : 0 }
        let h = height(container: container, safeBottom: safeBottom,
                       expanded: expanded, drag: drag)
        return min(1, max(0, (h - small) / (large - small)))
    }

    /// Kartenradius → Bildschirmradius.
    static func cornerRadius(progress: CGFloat, safeBottom: CGFloat) -> CGFloat {
        let target = screenCornerRadius(safeBottom: safeBottom)
        let t = min(1, max(0, progress))
        return cardRadius + (target - cardRadius) * t
    }

    /// Wie weit die Tafel seitlich ÜBER ihren Kasten hinausragt. Der Kasten
    /// steht im selben Seitenrand wie die Leiste; bei voller Größe soll die
    /// Fläche bis an die Bildschirmkante gehen, also wächst der Überstand auf
    /// genau diesen Rand.
    static func sideOverhang(progress: CGFloat, gutter: CGFloat) -> CGFloat {
        gutter * min(1, max(0, progress))
    }

    /// Wie weit die Tafel nach UNTEN über ihren Kasten hinausragt: bei voller
    /// Größe bis an die Bildschirmunterkante, also über die Leiste hinweg
    /// (Leiste plus die beiden Abstände plus die untere Sicherheitszone).
    /// Die Leiste selbst bleibt sichtbar — sie wird NACH der Tafel gezeichnet
    /// und liegt damit auf ihr.
    static func bottomOverhang(progress: CGFloat,
                               safeBottom: CGFloat,
                               bar: CGFloat,
                               gap: CGFloat) -> CGFloat {
        (max(0, safeBottom) + bar + 2 * gap) * min(1, max(0, progress))
    }

    /// Unterer Innenabstand des Tafel-INHALTS, wenn der Inhalt dauerhaft in
    /// seiner VOLLEN Höhe steht (siehe MorePanelSurface: die Liste wird
    /// einmal für die ganze Seite gelayoutet und nur noch FREIGELEGT — sie
    /// rechnet damit während eines Zuges kein einziges Mal neu).
    ///
    /// Zwei Anteile, beide am ZIEL-Zustand gerechnet, nie am laufenden Zug:
    ///  * der Teil der vollen Höhe, der im kleinen Zustand hinter der
    ///    Schnittkante liegt (`large − small`) — sonst endete die Liste
    ///    unerreichbar unterhalb der sichtbaren Karte;
    ///  * auf der ganzen Seite der Überstand unter der Leiste
    ///    (`bottomOverhang(1)`), aus demselben Grund wie bisher.
    static func contentBottomInset(container: CGFloat,
                                   safeBottom: CGFloat,
                                   expanded: Bool,
                                   bar: CGFloat,
                                   gap: CGFloat) -> CGFloat {
        let small = collapsedHeight(container: container)
        let large = expandedHeight(container: container, safeBottom: safeBottom)
        let hidden = expanded ? 0 : max(0, large - small)
        let overhang = bottomOverhang(progress: expanded ? 1 : 0,
                                      safeBottom: safeBottom, bar: bar, gap: gap)
        return hidden + overhang
    }

    // MARK: – Was die LEISTE dabei macht
    //
    // Auf der KARTE liegt die Leiste bewusst AUF dem unteren Überstand der
    // Tafel: die Tafel wächst aus ihr heraus, und ein Umschalter, der dabei
    // unter die eigene Tafel rutscht, sähe aus wie ein Fehler. Auf der GANZEN
    // SEITE stimmt genau das nicht mehr — dort gibt es kein „daneben" mehr,
    // über dem etwas schweben dürfte, und Umschalter und Anlegen-Knopf stehen
    // mitten in einer bildschirmfüllenden Fläche.
    //
    // Deshalb zieht sich die Leiste zurück, und zwar am SELBEN `progress` wie
    // Höhe, Radius und Überstand. Keine zweite Feder, kein zweiter Zustand:
    // eine Geste, eine Bewegung. (Eine eigene Animation auf derselben Geste
    // war schon einmal die Ursache des Nachziehens.)
    //
    // Was dabei NICHT verschwindet, ist der Griff — er ist auf der ganzen
    // Seite der einzige Weg zurück, und der liegt IN der Tafel.

    /// Bis hierhin steht die Leiste vollständig da. Solange die Tafel noch
    /// wie eine Karte aussieht, gehört sie ins Bild.
    static let chromeHold: CGFloat = 0.45
    /// Ab hier ist sie ganz weg — bewusst VOR dem Ende: die letzten Prozent
    /// der Fahrt sollen eine leere Fläche zeigen, nicht einen Knopf, der noch
    /// eben verglüht.
    static let chromeGone: CGFloat = 0.95

    /// 0 = die Leiste steht, 1 = sie ist fort. Der gemeinsame Verlauf hinter
    /// Deckkraft, Versatz und Trefferbarkeit — damit die drei nicht
    /// auseinanderlaufen können.
    static func chromeWithdrawal(progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, progress))
        guard t > chromeHold else { return 0 }
        guard chromeGone > chromeHold else { return 1 }
        return min(1, (t - chromeHold) / (chromeGone - chromeHold))
    }

    /// Deckkraft von Umschalter und Anlegen-Knopf.
    static func chromeOpacity(progress: CGFloat) -> Double {
        Double(1 - chromeWithdrawal(progress: progress))
    }

    /// Wie weit die Leiste dabei nach unten aus dem Bild fährt. Sie
    /// verschwindet nicht auf der Stelle, sie geht dorthin, wo sie herkam —
    /// das ist dieselbe Richtung, in die die Tafel beim Schließen fällt.
    ///
    /// Die Strecke reicht bis unter die Bildschirmkante: Leiste plus ihr
    /// Abstand nach unten plus die untere Sicherheitszone.
    static func chromeOffset(progress: CGFloat,
                             bar: CGFloat,
                             gap: CGFloat,
                             safeBottom: CGFloat) -> CGFloat {
        chromeWithdrawal(progress: progress) * (bar + gap + max(0, safeBottom))
    }

    /// Nimmt die Leiste noch Tipper an?
    ///
    /// Das ist keine Kosmetik zur Deckkraft: eine Ansicht mit `opacity(0)`
    /// ist in SwiftUI weiterhin TREFFBAR. Ohne diese Zeile läge auf der
    /// ganzen Seite ein unsichtbarer Anlegen-Knopf über der Tafel, und ein
    /// Tipp dorthin öffnete das Anlegen-Blatt aus dem Nichts.
    static func chromeInteractive(progress: CGFloat) -> Bool {
        chromeWithdrawal(progress: progress) < 0.5
    }

    // MARK: – Der Griff

    /// Maße des Griffs. Etwas breiter als die 36 pt der System-Blätter: er
    /// ist hier nicht nur ein Hinweis, sondern auf der ganzen Seite der
    /// EINZIGE Weg zurück.
    static let grabberWidth: CGFloat = 40
    static let grabberHeight: CGFloat = 5

    /// Deckkraft des Griffs auf `Color.primary` (schwarz im Hellen, weiß im
    /// Dunklen).
    ///
    /// Warum nicht `.tertiary`: die hierarchischen Stufen sind in BEIDEN
    /// Schemata gleich stark (rund 0,3), und das ist auf dem dunklen
    /// Tafelglas zu wenig — die Rückmeldung war „im Dunkeln kaum zu sehen".
    /// Ein heller Strich auf dunklem Grund braucht mehr Deckkraft als ein
    /// dunkler auf hellem, weil das Glas im Dunkeln aufhellt und im Hellen
    /// abdunkelt: es läuft dem Griff beide Male entgegen, aber im Dunkeln
    /// stärker. Im Hellen bleibt es deshalb fast beim alten Wert (dort war
    /// nie etwas falsch), im Dunkeln geht es deutlich hoch.
    static func grabberOpacity(dark: Bool) -> Double {
        dark ? 0.62 : 0.34
    }

    /// Wie viel Zug nach unten aus dem GROSSEN Zustand aufs Schrumpfen
    /// entfällt, bevor die Tafel zu wandern beginnt: der Höhenunterschied
    /// zwischen ganzer Seite und Karte. DIE Zahl, die den Zug vom großen
    /// Zustand mit dem vom kleinen zu EINEM Weg verkettet — Versatz und
    /// `resolve` rechnen beide mit ihr, damit die Geste und ihre Auflösung
    /// dieselbe Karte an derselben Stelle sehen.
    static func shrinkTravel(container: CGFloat, safeBottom: CGFloat) -> CGFloat {
        expandedHeight(container: container, safeBottom: safeBottom)
            - collapsedHeight(container: container)
    }

    /// Der senkrechte Versatz während eines Zuges: nur nach UNTEN.
    ///
    ///  * Aus dem KLEINEN Zustand wandert die Tafel sofort mit dem Finger.
    ///  * Aus dem GROSSEN ist der Zug erst das Schrumpfen selbst (siehe
    ///    `height`) — gewandert wird erst, wenn das Schrumpfen aufgebraucht
    ///    ist (`shrinkTravel`). Zu jedem Zeitpunkt bewegt sich genau EINE
    ///    Größe: erst die Höhe, dann der Versatz — nie beide. Vorher gab es
    ///    aus dem großen Zustand GAR keinen Versatz, und der Finger lief ab
    ///    der Kartenhöhe ins Leere.
    static func offset(container: CGFloat,
                       safeBottom: CGFloat,
                       expanded: Bool,
                       drag: CGFloat) -> CGFloat {
        guard drag > 0 else { return 0 }
        guard expanded else { return drag }
        return max(0, drag - shrinkTravel(container: container, safeBottom: safeBottom))
    }

    /// Was ein losgelassener Zug bedeutet.
    enum Outcome: Equatable { case expand, collapse, dismiss }

    /// `drag` ist die Translation beim Loslassen, `predicted` die
    /// vorhergesagte Endposition (der Wurf). `travel` ist `shrinkTravel` des
    /// Geräts, wenn der Zug im GROSSEN Zustand begann, sonst 0: die Karte
    /// liegt aus dem großen Zustand nicht bei 0, sondern bei `travel`, und
    /// die Schließ-Schwellen zählen AB der Karte — nicht ab dem Startpunkt.
    ///
    /// Aufgelöst wird EINMAL, nach Position UND Wurf, in genau eine von drei
    /// Ruhelagen. Es gibt keine Kaskade „erst zur Karte, dann von dort
    /// schließen" mehr: wer langsam bis unten zieht, ist beim Loslassen
    /// bereits hinter der Karte, und genau dort wird auch entschieden. Die
    /// Karte gewinnt nur noch, wenn der Zug IN ihrem Band endet — das ist
    /// dann kein erzwungener Zwischenhalt, sondern das richtige Ergebnis.
    static func resolve(drag: CGFloat,
                        predicted: CGFloat,
                        expanded: Bool,
                        travel: CGFloat = 0) -> Outcome {
        let up = drag < -snapDistance || predicted < -flickDistance
        let down = drag > snapDistance || predicted > flickDistance
        if up { return .expand }
        guard down else { return expanded ? .expand : .collapse }
        // Nach unten: hinter der Karte (plus Schwelle) ist es ein Schließen,
        // davor ein Einrasten auf der Karte. Ein Wurf zählt wie überall als
        // Strecke — ein schneller kurzer Zug vom ganzen Bild schließt sofort,
        // ohne an der Karte vorbeizumüssen.
        let beyondCard = max(0, travel)
        return (drag > beyondCard + dismissDistance
                || predicted > beyondCard + flickDistance) ? .dismiss : .collapse
    }
}
