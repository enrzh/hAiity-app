import SwiftUI

/// Habit-Karte, seit v3 umgedreht: in der Fläche steckt NUR noch das Raster
/// (samt Monatsmarken). Name, Emoji, Nebendaten, der Heute-Knopf und das Menü
/// stehen darüber nackt auf dem App-Hintergrund — das Raster ist der Held,
/// der Rest ist Beschriftung und braucht kein eigenes Kärtchen.
///
/// Die Kopfzeile ist EINE Zeile:
///
///     📚  Lesen   🕐 19:00  🔥 12            ✓ Erledigt   ⋯
///     └ Name zuerst ┘└ Nebendaten sekundär ┘  └ Aktion ┘  └ Menü ┘
///
/// Uhrzeit und Serie sind Nebendaten und stehen deshalb als kleine
/// Symbol-Zahl-Paare direkt hinter dem Namen — auf der Grundlinie des Namens,
/// in `.secondary`. Sie bekommen KEINE eigene Zeile: eine zweite Zeile nur
/// für „🕐 19:00" hat die Karte früher schief aussehen lassen und Karten mit
/// und ohne Uhrzeit unterschiedlich hoch gemacht.
///
/// `collapsed` kommt vom Scroll-Zustand der Liste (ContentView misst ihn aus
/// den Zeilenpositionen): beim Scrollen zieht sich der Kopf auf den linken
/// Namen zusammen — Nebendaten weg, Name und Knopf eine Stufe kleiner, und
/// die Zeile wird flacher (44 -> 32 pt), samt der Abstände darum. Ein Kopf,
/// der beim Scrollen seine ausgeklappte Höhe behält, steht als leerer Kasten
/// über dem Raster; genau das war die Rückmeldung. Der Preis: die Zeilen
/// ändern beim Umschalten ihre Höhe und schieben einander — die Messung in
/// `ChromeScroll` setzt dafür kurz aus (Nachlaufsperre).
struct HabitCard: View {
    let habit: Habit
    /// Zusammengezogener Kopf (beim Scrollen). Standard `false`, damit
    /// Vorschauen und Tests die Karte ohne Scroll-Kontext bauen können.
    var collapsed: Bool = false
    let onToggleDay: (String) -> Void
    let onIncrement: () -> Void
    let onClear: () -> Void
    /// Abhaken bzw. hochzählen — hakt nur AN, nie ab (die Umkehrung heißt
    /// „Rückgängig" und ist `onClear`).
    let onMarkDone: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Klammert Pille und verschmolzenen Zustand zusammen, damit das eine ins
    /// andere fliegt statt zu blinken.
    @Namespace private var doneNamespace
    private static let doneID = "done"

    private var today: String { DayKey.today() }
    private var doneToday: Bool { GoalEngine.dayCounts(habit: habit, day: today) }

    /// Höhe der Kopfzeile. Ausgeklappt volle Trefferfläche, zusammengezogen
    /// deutlich flacher — der Kopf soll beim Scrollen nicht als leerer Kasten
    /// über dem Raster stehen bleiben. Als Frame-Höhe (nicht als
    /// Zeilen-Inset) gesetzt, damit der Wert im Übergang INTERPOLIERT.
    private var headerHeight: CGFloat { collapsed ? 32 : Theme.Metrics.hit }

    /// Abstand Kopf -> eigenes Raster. Klein und absichtlich: der Kopf
    /// gehört zur Fläche DARUNTER.
    private var innerGap: CGFloat { collapsed ? 4 : Theme.Metrics.gap }

    /// Abstand zur nächsten Karte — immer ein Vielfaches des inneren
    /// Abstands, sonst liest sich der freistehende Kopf als Fußzeile der
    /// vorigen Karte statt als Überschrift der eigenen.
    private var outerGap: CGFloat { collapsed ? 12 : Theme.Metrics.gutter }

    var body: some View {
        VStack(alignment: .leading, spacing: innerGap) {
            header
                // Der Schlucker liegt HINTER dem Kopf, nicht darüber: die
                // Knöpfe darin (Heute-Pille, drei Punkte) sind gezeichnete
                // Geschwister WEITER VORN und bekommen ihre Tipps zuerst.
                // Ein Overlay — oder eine Geste auf dem Kopf selbst — nimmt
                // sie ihnen weg (nachgemessen: die Pille reagierte dann
                // nicht mehr).
                .background { longPressSink }
            grid
        }
        // Der Zeilenabstand steckt bewusst HIER und nicht in `listRowInsets`:
        // Insets springen beim Umschalten, ein Padding wird animiert.
        .padding(.top, 4)
        .padding(.bottom, outerGap)
        // `.contain` ist hier Pflicht, nicht Deko: ein Identifier auf einem
        // Container ohne diese Angabe faltet den Teilbaum zu EINEM Element
        // zusammen — "check-today" und "edit-habit" verschwinden dann aus
        // dem Baum und sind in XCUITest nicht mehr adressierbar. Als
        // Container bleibt die Karte selbst auffindbar UND ihre Knöpfe.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habit-card")
    }

    // MARK: – Raster in der Fläche

    /// Das Einzige, was noch Karte ist — UND die einzige Fläche, die auf
    /// langen Druck reagiert.
    ///
    /// Das Menü hing einmal an der ganzen Zeile. Das war zu viel: der Kopf
    /// ist eine Werkzeugleiste (Name, Heute-Knopf, drei Punkte), und ein
    /// langer Druck darauf schob die Vorschau über genau die Knöpfe, die man
    /// treffen wollte. Jetzt ist die Fläche des Rasters die Fläche der Geste
    /// — dieselbe Fläche, die die Vorschau auch zeigt.
    ///
    /// Der Tipp auf eine EINZELNE Zelle überlebt das: `contextMenu` erkennt
    /// den langen Druck und lässt kurze Tipps zu seinen Kindern durch (die
    /// Zellen haben ihre eigenen `onTapGesture` in `ContributionGrid`).
    private var grid: some View {
        ContributionGrid(habit: habit, onToggle: onToggleDay)
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                             style: .continuous))
            // Die Trefferfläche ist die KARTE, nicht nur das, was in ihr
            // gezeichnet ist: ein langer Druck auf eine leere Ecke des
            // Rasters soll dasselbe tun wie einer auf eine Zelle.
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                           style: .continuous))
            // LANGER DRUCK: statt einer unsichtbaren Wischbelegung, die man
            // sich merken muss, eine VORSCHAU mit dem vergrößerten Raster und
            // darunter die Aktionen, beschriftet. Das System liefert dafür
            // die Standardanimation (Herausschälen) und die Haptik.
            .contextMenu {
                habitActions
            } preview: {
                habitPreview
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("habit-grid")
    }

    // MARK: – Langer Druck: Vorschau + Aktionen
    //
    // Die Vorschau zeigt DASSELBE Bauteil wie die Zeile (ContributionGrid),
    // nur an einem größeren Maß: 20-pt-Zellen statt der ~11 pt, die in eine
    // Listenzeile passen. Ein nachgebautes „Vorschau-Raster" würde beim
    // nächsten Anfassen des echten auseinanderlaufen — hier kann es das
    // nicht. Die Vorschau ist zum ANSEHEN da, nicht zum Blättern
    // (`interactive: false`).
    //
    // **Sie ist so breit wie der Bildschirm** (minus einem schmalen Rand).
    // Eine Vorschau, die sich auf ihren Inhalt zusammenzieht, stand vorher
    // als halbbreite Karte in der Mitte — bei einem Bauteil, dessen ganzer
    // Sinn die BREITE ist (ein Jahr von links nach rechts), ist das die
    // falsche Form. Die Breite ist deshalb explizit gesetzt, und die
    // Wochenzahl fällt aus ihr: mehr Platz heißt mehr Historie, nicht
    // dasselbe Raster in einer größeren Schachtel.

    static let previewCell: CGFloat = 20
    static let previewGap: CGFloat = 4
    /// Rand zwischen Vorschau und Bildschirmkante.
    static let previewMargin: CGFloat = 16
    /// Untergrenze für sehr schmale Fenster (Slide-Over).
    static let previewMinWidth: CGFloat = 260

    /// Breite des AKTIVEN Fensters, nicht `UIScreen.main.bounds`: das ist
    /// die Größe des Bildschirms, nicht die der App — im Split View auf dem
    /// iPad wäre die Vorschau damit breiter als das Fenster, in dem sie
    /// steht. Nur wenn gar keine Szene erreichbar ist, fällt es auf den
    /// Bildschirm zurück.
    private static func windowWidth() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let width = scene?.keyWindow?.bounds.width, width > 0 { return width }
        if let width = scene?.screen.bounds.width, width > 0 { return width }
        return UIScreen.main.bounds.width
    }

    /// Breite und Wochenzahl der Vorschau aus der FENSTERBREITE. Als reine
    /// Funktion, weil sie auf einem SE (375 pt) und auf einem Max (440 pt)
    /// stimmen muss und ein Screenshot je Gerät keine Prüfung ist.
    ///
    /// Die Wochenzahl fällt aus der Breite: Innenmaß geteilt durch das
    /// Rastermaß (Zelle + Lücke). Mehr als 53 gibt es nicht — das Raster IST
    /// ein Jahr.
    static func previewMetrics(windowWidth: CGFloat) -> (width: CGFloat, weeks: Int) {
        let width = max(previewMinWidth, windowWidth - 2 * previewMargin)
        let content = width - 2 * Theme.Metrics.gutter
        let pitch = previewCell + previewGap
        let weeks = min(53, max(8, Int((content + previewGap) / pitch)))
        return (width, weeks)
    }

    private var previewWidth: CGFloat { Self.previewMetrics(windowWidth: Self.windowWidth()).width }
    private var previewWeeks: Int { Self.previewMetrics(windowWidth: Self.windowWidth()).weeks }

    private var habitPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !habit.emoji.isEmpty { Text(habit.emoji).font(.title3) }
                Text(habit.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if habit.streak() > 0 {
                    (Text(Image(systemName: "flame.fill")) + Text(verbatim: " \(habit.streak())"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ContributionGrid(habit: habit,
                             weeks: previewWeeks,
                             cellSize: Self.previewCell,
                             gap: Self.previewGap,
                             interactive: false)
        }
        .padding(Theme.Metrics.gutter)
        .frame(width: previewWidth)
        .background(Color(.secondarySystemGroupedBackground))
        // Die Vorschau ist eine EIGENE Präsentation und erbt die Umgebung
        // der Zeile nicht: ohne diese Zeile fiel das Raster darin auf die
        // Standardpalette zurück und leuchtete grün, während dieselben
        // Zellen zwei Millimeter daneben blau sind.
        .environment(\.palettes, palettes)
        // Der einzige verlässliche Aufhänger dafür, dass die Vorschau WIRKLICH
        // aufgegangen ist — das System sagt es sonst nicht. Dieselbe kurze
        // Rückmeldung wie beim Abhaken.
        .onAppear { Theme.Haptics.check() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habit-preview")
    }

    /// Die Aktionen UNTER der Vorschau. Sie tragen dieselben Kennungen wie
    /// die Knöpfe auf der Karte (`check-today`, `edit-habit`) — was über den
    /// langen Druck erreichbar ist, muss unter demselben Namen erreichbar
    /// sein wie direkt auf der Zeile.
    @ViewBuilder
    private var habitActions: some View {
        if doneToday, habit.recurrence.target == nil {
            Button(action: onClear) {
                Label(String(localized: "Rückgängig"), systemImage: "arrow.uturn.backward")
            }
            .accessibilityIdentifier("check-today")
        } else {
            Button(action: onMarkDone) {
                Label(String(localized: "Erledigt"), systemImage: "checkmark")
            }
            .accessibilityIdentifier("check-today")
            // Mengenziele zählen hoch; das Zurücksetzen des Tages steht
            // deshalb zusätzlich daneben, sobald es etwas zurückzusetzen gibt.
            if habit.recurrence.target != nil, (habit.log[today] ?? 0) > 0 {
                Button(action: onClear) {
                    Label(String(localized: "Rückgängig"), systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("revert-today")
            }
        }
        Button(action: onEdit) {
            Label(String(localized: "Bearbeiten"), systemImage: "pencil")
        }
        .accessibilityIdentifier("edit-habit")
        Button(action: onArchive) {
            Label(String(localized: "Archivieren"), systemImage: "archivebox")
        }
        .accessibilityIdentifier("archive-habit")
        ShareLink(item: HabitShareImage(habit: habit,
                                        dark: scheme == .dark,
                                        palette: palettes.style(for: habit)),
                  preview: SharePreview(habit.name)) {
            Label(String(localized: "Als Bild teilen"), systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("share-habit")
    }

    // MARK: – Kopf auf nacktem Grund

    /// Ab den Accessibility-Größen bricht die Zeile um: der Name bekommt die
    /// volle Breite, Nebendaten und Knöpfe rutschen darunter. In einer Zeile
    /// bliebe bei XXL nur noch "La…" vom Habit-Namen übrig.
    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                nameRun
                HStack(spacing: Theme.Metrics.gap) {
                    Spacer(minLength: 0)
                    todayButton
                    editButton
                }
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
        } else {
            HStack(spacing: Theme.Metrics.gap) {
                nameRun
                Spacer(minLength: Theme.Metrics.gap)
                // Zusammengezogen bleiben NUR Name (mit verschmolzenem
                // Heute-Zustand) und die drei Punkte.
                if !collapsed { todayButton }
                editButton
            }
            .frame(height: headerHeight)
            // Auf die Innenkante der Rasterfläche ausgerichtet: Name und
            // erste Rasterspalte stehen in EINER Flucht.
            .padding(.horizontal, Theme.Metrics.cardPadding)
        }
    }

    /// **Warum der Kopf einen langen Druck schluckt.**
    ///
    /// Das Kontextmenü hängt am RASTER (siehe `grid`) — in einer `List` hilft
    /// das allein aber nichts: SwiftUI hebt ein `contextMenu` aus dem
    /// Zeileninhalt auf die ZELLE, und die ist die ganze Zeile. Nachgemessen:
    /// ein langer Druck auf den Namen öffnete das Menü weiterhin, obwohl der
    /// Modifier zwei Ebenen tiefer sitzt.
    ///
    /// Ein eigener Langdruck HINTER dem Kopf gewinnt die Erkennung gegen die
    /// Zelle (der tiefere Erkenner hat Vorrang) und tut NICHTS. Damit bleibt
    /// die Geste dem Raster vorbehalten — dem Bauteil, das die Vorschau auch
    /// zeigt.
    private var longPressSink: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration: 0.22).onEnded { _ in })
            .accessibilityHidden(true)
    }

    /// Name zuerst, Nebendaten dahinter — auf DERSELBEN Schriftgrundlinie,
    /// nicht auf gleicher Kastenmitte. Deshalb `.firstTextBaseline` und
    /// Symbole, die als Teil des Textes gesetzt sind.
    ///
    /// Zusammengezogen ist dieser Lauf SELBST der Heute-Knopf: die Pille
    /// wandert per `matchedGeometryEffect` in den Namen und wird dort zum
    /// Häkchen davor (Checkbox) bzw. zum Zähler dahinter (Mengenziel). Damit
    /// bleibt das Abhaken auch beim Scrollen erreichbar — und `check-today`
    /// steht in jedem Zustand genau einmal im Baum.
    private var nameRun: some View {
        Button {
            Theme.Haptics.check()
            if habit.recurrence.target != nil { onIncrement() } else { onToggleDay(today) }
        } label: {
            nameContent
        }
        .buttonStyle(.plain)
        // Der Knopf steht in BEIDEN Zuständen im Baum und wird ausgeklappt
        // nur stillgelegt. Ein `if collapsed { Button } else { … }` wäre für
        // SwiftUI ein anderer View: der Name würde beim Umschalten
        // übergeblendet (zwei Namen übereinander) statt zu interpolieren.
        .allowsHitTesting(collapsed)
        .accessibilityIdentifier(collapsed ? "check-today" : "habit-name")
        .accessibilityLabel(collapsed ? collapsedActionLabel : habit.name)
        .accessibilityRemoveTraits(collapsed ? [] : .isButton)
    }

    private var nameContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !habit.emoji.isEmpty {
                Text(habit.emoji)
                    .font(collapsed ? .subheadline : .title3)
            }
            Text(habit.name)
                .font(collapsed ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            // Der Zustand steht HINTER dem Namen, nicht davor: sonst rückt
            // ein Häkchen die Namen der abgehakten Karten ein und die Liste
            // fluchtet nicht mehr.
            if collapsed { mergedDone }
            if !collapsed { meta.fixedSize() }
        }
        .contentShape(Rectangle())
    }

    /// Der Heute-Zustand, IM Namen. Kein gefülltes Pillchen mehr: ein Häkchen
    /// vor dem Namen (Checkbox) oder ein Zähler dahinter (Mengenziel), beides
    /// klein und in Akzent- bzw. Sekundärfarbe. Dieselbe
    /// `matchedGeometryEffect`-Kennung wie die Pille — deshalb FLIEGT die
    /// Pille beim Zusammenziehen in den Namen, statt dort auszublenden und
    /// hier neu aufzublitzen.
    @ViewBuilder
    private var mergedDone: some View {
        if let target = habit.recurrence.target {
            let value = habit.log[today] ?? 0
            Text(verbatim: "\(value)/\(target)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(doneToday
                                 ? AnyShapeStyle(Theme.accentText(palettes.style))
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
        } else {
            Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundStyle(doneToday
                                 ? AnyShapeStyle(Theme.accentText(palettes.style))
                                 : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
        }
    }

    private var collapsedActionLabel: String {
        if let target = habit.recurrence.target {
            return String(localized: "Heute: \(habit.log[today] ?? 0) von \(target)")
        }
        return doneToday ? String(localized: "✓ Erledigt") : String(localized: "Heute")
    }

    /// Uhrzeit, Serie und — wenn heute gar kein Termin ist — der nächste.
    /// Alle drei nur, wenn sie etwas zu sagen haben: eine Serie von 0 ist
    /// keine Serie, ohne Uhrzeit fehlt die Uhr ersatzlos, und bei einem
    /// Habit, das heute ohnehin dran ist, steht kein Kalender.
    ///
    /// Hier stand bis v4 eine GLOCKE mit der Zeit der eigenen Erinnerung.
    /// Die gibt es nicht mehr (erinnert wird zentral, siehe `Reminders`) —
    /// eine Glocke, die nichts mehr auslöst, wäre eine Lüge. An ihrer Stelle
    /// steht jetzt die Uhrzeit des Termins selbst, mit einer Uhr davor.
    ///
    /// Das ist die EINZIGE Stelle, an der die Liste zwischen „heute fällig"
    /// und „heute frei" unterscheidet. Die Heute-Kontrolle bleibt bewusst
    /// bedienbar: wer an einem freien Tag trotzdem läuft, darf das abhaken
    /// (es zählt auch — siehe GoalEngine).
    @ViewBuilder
    private var meta: some View {
        let streak = habit.streak()
        if timeText != nil || streak > 0 || nextDueLabel != nil {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.gap) {
                if let time = timeText {
                    metaItem("clock", time,
                             label: String(localized: "Um \(time)"))
                }
                if streak > 0 {
                    metaItem("flame.fill", "\(streak)",
                             label: String(localized: "Serie: \(streak) Tage"))
                }
                if let next = nextDueLabel {
                    metaItem("calendar", next.short,
                             label: String(localized: "Heute frei, nächster Termin: \(next.long)"))
                }
            }
            .padding(.leading, 2)
            .transition(.opacity)
        }
    }

    /// „Heute ist nichts fällig, als Nächstes am Montag." nil, sobald heute
    /// ein Termin ist — dann sagt die Heute-Kontrolle schon alles.
    private var nextDueLabel: (short: String, long: String)? {
        guard !GoalEngine.isScheduled(habit: habit, day: today) else { return nil }
        guard let next = habit.recurrence.nextOccurrence(after: today),
              let date = DayKey.date(from: next) else {
            return (String(localized: "frei"), String(localized: "keiner mehr"))
        }
        let weekday = Calendar.current.component(.weekday, from: date)
        return (RecurrenceText.shortWeekdayName(weekday),
                RecurrenceText.weekdayName(weekday))
    }

    /// Symbol und Zahl als EIN Textlauf — so sitzt das Glyph automatisch auf
    /// der Grundlinie der Ziffern statt auf der Mitte seines Kastens.
    private func metaItem(_ symbol: String, _ value: String, label: String) -> some View {
        (Text(Image(systemName: symbol)) + Text(verbatim: " \(value)"))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
    }

    /// Heute-Kontrolle im ausgeklappten Zustand: Checkbox toggelt, Mengenziel
    /// zählt hoch. Zusammengezogen gibt es diese Pille nicht mehr — sie ist
    /// dann im Namen aufgegangen (siehe `mergedDone`).
    @ViewBuilder
    private var todayButton: some View {
        if let target = habit.recurrence.target {
            let value = habit.log[today] ?? 0
            Button {
                Theme.Haptics.check()
                onIncrement()
            } label: {
                pill("\(value)/\(target)", monospaced: true)
            }
            .buttonStyle(.plain)
            // KEIN eigenes Kontextmenü mehr: der lange Druck gehört der
            // ganzen Zeile. Zwei verschachtelte Menüs auf derselben Karte
            // hießen, dass ein langer Druck je nach getroffenem Pixel etwas
            // anderes tut. „Rückgängig" steht im Zeilenmenü.
            .accessibilityLabel(String(localized: "Heute: \(value) von \(target)"))
            .accessibilityIdentifier("check-today")
        } else {
            Button {
                Theme.Haptics.check()
                onToggleDay(today)
            } label: {
                pill(doneToday ? String(localized: "✓ Erledigt") : String(localized: "Heute"))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneToday
                                ? String(localized: "✓ Erledigt")
                                : String(localized: "Heute"))
            .accessibilityIdentifier("check-today")
        }
    }

    /// Die Pille ist SICHTBAR klein, die Trefferfläche trotzdem so hoch wie
    /// die Kopfzeile.
    private func pill(_ text: String, monospaced: Bool = false) -> some View {
        let base = Font.subheadline.weight(.semibold)
        return Text(verbatim: text)
            .font(monospaced ? base.monospacedDigit() : base)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(doneToday ? Theme.accentFill(palettes.style) : Color(.tertiarySystemFill),
                        in: Capsule())
            .foregroundStyle(doneToday ? .white : .primary)
            .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
            .frame(height: headerHeight)
            .contentShape(Rectangle())
    }

    /// Das Glyph steht an der TRAILING-Kante seiner 44er-Trefferfläche —
    /// damit fluchtet es mit der rechten Innenkante des Rasters, während der
    /// Finger die vollen 44 pt bekommt.
    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "ellipsis")
                .font(collapsed ? .caption : .footnote)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Metrics.hit, height: headerHeight,
                       alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(habit.name) bearbeiten"))
        .accessibilityIdentifier("edit-habit")
    }

    /// Die Uhrzeit des Habits — dieselbe Formatierung wie im Regel-Satz,
    /// damit „um 07:30" auf der Karte und im Editor gleich aussieht.
    private var timeText: String? { RecurrenceText.timeText(habit.timeMinutes) }
}
