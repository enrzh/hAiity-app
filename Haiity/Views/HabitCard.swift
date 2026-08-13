import SwiftUI

/// Habit-Karte, seit v3 umgedreht: in der Fläche steckt NUR noch das Raster
/// (samt Monatsmarken). Name, Emoji, Nebendaten und der Heute-Knopf
/// stehen darüber nackt auf dem App-Hintergrund — das Raster ist der Held,
/// der Rest ist Beschriftung und braucht kein eigenes Kärtchen.
///
/// Die Kopfzeile ist EINE Zeile:
///
///     📚  Lesen   🕐 19:00  🔥 12            ✓ Erledigt
///     └ Name zuerst ┘└ Nebendaten sekundär ┘  └ Aktion ┘
///
/// Uhrzeit und Serie sind Nebendaten und stehen deshalb als kleine
/// Symbol-Zahl-Paare direkt hinter dem Namen — auf der Grundlinie des Namens,
/// in `.secondary`. Sie bekommen KEINE eigene Zeile: eine zweite Zeile nur
/// für „🕐 19:00" hat die Karte früher schief aussehen lassen und Karten mit
/// und ohne Uhrzeit unterschiedlich hoch gemacht.
///
/// `collapsed` kommt aus der persistenten Ansichts-Einstellung: der Kopf zieht sich auf den linken
/// Namen zusammen — Nebendaten weg, Name und Knopf eine Stufe kleiner, und
/// die Zeile wird flacher (44 -> 32 pt), samt der Abstände darum. Ein Kopf,
/// der beim Scrollen seine ausgeklappte Höhe behält, steht als leerer Kasten
/// über dem Raster; genau das war die Rückmeldung. Der Preis: die Zeilen
/// ändern beim Umschalten ihre Höhe und schieben einander.
/// `Equatable` aus demselben Grund wie `ContributionGrid`: die Karte hängt
/// sichtbar nur an `habit` und `collapsed` — ihre Closures sind Verhalten,
/// bei jeder Auswertung des Aufrufers frisch gebaut und semantisch dieselben.
/// Ohne den Vergleich reißt jede `ContentView`-Auswertung (Tafel auf/zu,
/// Toast, Sync-Pille) alle sichtbaren Karten mit.
struct HabitCard: View, Equatable {
    static func == (a: HabitCard, b: HabitCard) -> Bool {
        a.habit == b.habit && a.collapsed == b.collapsed
    }

    let habit: Habit
    /// Zusammengezogener Kopf. Standard `false`, damit Vorschauen und Tests
    /// die Karte ohne Einstellungs-Kontext bauen können.
    var collapsed: Bool = false
    /// Heute abhaken (Kopfzeile). Der einzige Weg von dieser Karte aus, der
    /// direkt schreibt — er sitzt auf einem beschrifteten Knopf.
    let onToggleDay: (String) -> Void
    /// Ein Tag im Raster wurde AUSGEWÄHLT. Schreibt nichts; der Aufrufer
    /// öffnet damit die Nacharbeiten-Karte an diesem Datum.
    let onSelectDay: (String) -> Void
    /// „Nacharbeiten" aus dem Kontextmenü — dieselbe Karte, aber ohne
    /// vorgewählten Tag (sie öffnet auf heute). Eigener Weg, weil er ERST
    /// nach dem Schließen des Menüs greifen darf.
    let onBackfill: () -> Void
    let onIncrement: () -> Void
    let onClear: () -> Void
    /// Abhaken bzw. hochzählen — hakt nur AN, nie ab (die Umkehrung heißt
    /// „Rückgängig" und ist `onClear`).
    let onMarkDone: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    /// Heute mit Ja bzw. Nein beantworten (Habit-Art „Ja/Nein"). Umschaltend:
    /// dieselbe Antwort ein zweites Mal nimmt sie zurück. Steht mit einem
    /// Standardwert ganz am Ende, damit Vorschauen und Tests die Karte ohne
    /// diesen Weg bauen können.
    var onAnswer: (Bool) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Klammert Pille und verschmolzenen Zustand zusammen, damit das eine ins
    /// andere fliegt statt zu blinken.
    @Namespace private var doneNamespace
    private static let doneID = "done"

    private var today: String { DayKey.today() }
    private var doneToday: Bool { GoalEngine.dayCounts(habit: habit, day: today) }
    private var declinedToday: Bool { habit.isDeclined(today) }
    /// Die Verneinungsfarbe DIESES Habits — dieselbe, die seine Zellen im
    /// Raster tragen. Der Kopf darf nicht in einer anderen Farbe „Nein"
    /// sagen als die Fläche darunter.
    private var negativeColor: Color {
        Theme.color(palettes.style(for: habit).negative(dark: scheme == .dark))
    }

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
        #if DEBUG
        let _ = FrameProbe.shared.mark("card.body")
        #endif
        return VStack(alignment: .leading, spacing: innerGap) {
            header
                // Der Schlucker liegt HINTER dem Kopf, nicht darüber: die
                // Knöpfe darin (Heute-Pille) sind gezeichnete
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
    /// ist eine Werkzeugleiste (Name und Heute-Knopf), und ein
    /// langer Druck darauf schob die Vorschau über genau die Knöpfe, die man
    /// treffen wollte. Jetzt ist die Fläche des Rasters die Fläche der Geste
    /// — dieselbe Fläche, die die Vorschau auch zeigt.
    ///
    /// Der Tipp auf eine EINZELNE Zelle überlebt das: die Langdruck-Geste
    /// lässt kurze Tipps zu ihren Kindern durch (die Zellen haben ihre
    /// eigenen `onTapGesture` in `ContributionGrid`). Er
    /// WÄHLT den Tag aus und öffnet die Nacharbeiten-Karte — er schreibt
    /// nicht.
    private var grid: some View {
        // `.equatable()` ist Tempo, nicht Kosmetik (dasselbe Muster wie die
        // Mehr-Liste in `MorePanelSurface`): ohne den Vergleich baut jede
        // Auswertung dieser Karte die 371 Zellen neu, auch wenn sich nur das
        // Chrom bewegt hat. Store-Änderungen kommen an — sie ändern `habit`.
        ContributionGrid(habit: habit, onSelectDay: onSelectDay)
            .equatable()
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
            // Der Halten-Popup ist das SYSTEM-Kontextmenü (dieselbe
            // Mechanik wie das Halten auf einem Link): Anheben der Karte,
            // große Vorschau, Menü darunter — und ein Tipp auf die Vorschau
            // COMMITTET zu Bearbeiten. SwiftUI kommt hier zweimal nicht
            // weiter: `.onLongPressGesture` feuert in dieser Verschachtelung
            // nie (List-Zelle, horizontale ScrollView im Raster), und
            // `.contextMenu(preview:)` kennt keinen Vorschau-Tipp. Deshalb
            // die UIKit-Interaktion selbst, angehängt an die Zelle (siehe
            // GraphContextMenu).
            .background {
                GraphContextMenu(cardRadius: Theme.Metrics.cardRadius,
                                 previewWidth: previewWidth,
                                 preview: { AnyView(habitPreview) },
                                 actions: menuActions,
                                 commit: onEdit)
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
                .equatable()
        }
        .padding(Theme.Metrics.gutter)
        .frame(width: previewWidth)
        .background(Color(.secondarySystemGroupedBackground))
        // Die Vorschau ist eine EIGENE Präsentation und erbt die Umgebung
        // der Zeile nicht: ohne diese Zeile fiel das Raster darin auf die
        // Standardpalette zurück und leuchtete grün, während dieselben
        // Zellen zwei Millimeter daneben blau sind.
        .environment(\.palettes, palettes)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habit-preview")
    }

    /// Die Einträge UNTER der System-Vorschau. Was über den langen Druck
    /// erreichbar ist, bleibt inhaltlich dasselbe wie zuvor im Blatt:
    /// Nacharbeiten, Session, Bearbeiten, Archivieren, Teilen.
    private var menuActions: [GraphMenuAction] {
        [GraphMenuAction(title: String(localized: "Nacharbeiten"),
                         symbol: "calendar.badge.plus",
                         handler: onBackfill),
         // Session: „ich mache das JETZT" — startet die Live-Aktivität.
         // Direkt am Manager statt als Closure aus ContentView — die Session
         // hat keinen UI-Zustand, den die Liste kennen müsste.
         GraphMenuAction(title: String(localized: "Session starten"),
                         symbol: "timer",
                         handler: { HabitSessionManager.shared.start(habit: habit) }),
         GraphMenuAction(title: String(localized: "Bearbeiten"),
                         symbol: "pencil",
                         handler: onEdit),
         GraphMenuAction(title: String(localized: "Archivieren"),
                         symbol: "archivebox",
                         handler: onArchive),
         GraphMenuAction(title: String(localized: "Als Bild teilen"),
                         symbol: "square.and.arrow.up",
                         handler: shareCard)]
    }

    /// Teilen aus einem UIMenu: das fertige Kartenbild in das System-Blatt.
    /// (ShareLink lebt in SwiftUI-Menüs — in einem UIMenu präsentieren wir
    /// das Activity-Blatt selbst, über dem obersten Controller.)
    private func shareCard() {
        guard let image = ShareCard.render(habit: habit,
                                           scheme: scheme == .dark ? .dark : .light,
                                           palette: palettes.style(for: habit)) else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?
            .keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(UIActivityViewController(activityItems: [image],
                                             applicationActivities: nil),
                    animated: true)
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
                }
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
        } else {
            HStack(spacing: Theme.Metrics.gap) {
                nameRun
                Spacer(minLength: Theme.Metrics.gap)
                // Zusammengezogen bleibt der Name mit verschmolzenem
                // Heute-Zustand.
                if !collapsed { todayButton }
            }
            .frame(height: headerHeight)
            // Auf die Innenkante der Rasterfläche ausgerichtet: Name und
            // erste Rasterspalte stehen in EINER Flucht.
            .padding(.horizontal, Theme.Metrics.cardPadding)
        }
    }

    /// **Warum der Kopf einen langen Druck schluckt.**
    ///
    /// Ein eigener Langdruck HINTER dem Kopf gewinnt die Erkennung und tut
    /// nichts. Damit bleibt die Geste dem Raster vorbehalten — dem Bauteil,
    /// das die Vorschau auch zeigt.
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
            switch habit.kind {
            // Zusammengezogen gibt es nur EINEN Tipp — er meint JA. Ein
            // Dreiklang (unbeantwortet -> Ja -> Nein -> …) auf einer
            // unsichtbaren Trefferfläche wäre geraten statt bedient; „Nein"
            // steht ausgeklappt und im Menü.
            case .yesNo:    onAnswer(true)
            case .quantity: onIncrement()
            case .checkbox: onToggleDay(today)
            }
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
        if habit.kind == .quantity, let target = habit.recurrence.target {
            let value = habit.log[today] ?? 0
            Text(verbatim: "\(value)/\(target)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(doneToday
                                 ? AnyShapeStyle(Theme.accentText(palettes.style))
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
        } else {
            // Drei Zustände, drei Glyphen — ein Ja/Nein-Habit darf im
            // zusammengezogenen Kopf nicht aussehen wie ein offener.
            Image(systemName: declinedToday
                  ? "xmark.circle.fill"
                  : (doneToday ? "checkmark.circle.fill" : "circle"))
                .font(.footnote)
                .foregroundStyle(declinedToday
                                 ? AnyShapeStyle(negativeColor)
                                 : (doneToday
                                    ? AnyShapeStyle(Theme.accentText(palettes.style))
                                    : AnyShapeStyle(HierarchicalShapeStyle.tertiary)))
                .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
        }
    }

    private var collapsedActionLabel: String {
        switch habit.kind {
        case .quantity:
            return String(localized: "Heute: \(habit.log[today] ?? 0) von \(habit.recurrence.target ?? 1)")
        case .yesNo:
            if declinedToday { return String(localized: "Heute: Nein") }
            return doneToday ? String(localized: "Heute: Ja") : String(localized: "Heute beantworten")
        case .checkbox:
            return doneToday ? String(localized: "✓ Erledigt") : String(localized: "Heute")
        }
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
        switch habit.kind {
        case .quantity:
            let target = habit.recurrence.target ?? 1
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
        case .yesNo:
            answerButtons
        case .checkbox:
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

    /// Zwei Knöpfe statt einer Pille. Eine Frage hat zwei Antworten, und
    /// beide müssen mit EINEM Finger erreichbar sein — sonst wäre „Nein" die
    /// Antwort, die man sich verdienen muss (Kontextmenü öffnen),
    /// und die Zahlen darunter wären systematisch zu freundlich.
    ///
    /// Symbole statt Text: „Ja"/„Nein" nebeneinander brauchen mehr Breite
    /// als die „✓ Erledigt"-Pille, die hier vorher stand, und die Zeile hat
    /// links den Namen zu tragen. Zwei 34-pt-Kreise sind zusammen so breit
    /// wie die Pille — die Kopfzeile behält also ihr Maß, unabhängig von der
    /// Art des Habits.
    private var answerButtons: some View {
        HStack(spacing: 6) {
            answerButton(yes: true)
            answerButton(yes: false)
        }
        .frame(height: headerHeight)
        .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
    }

    private func answerButton(yes: Bool) -> some View {
        let on = yes ? doneToday : declinedToday
        return Button {
            Theme.Haptics.check()
            onAnswer(yes)
        } label: {
            Image(systemName: yes ? "checkmark" : "xmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(on ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 34, height: 30)
                .background(on
                            ? AnyShapeStyle(yes ? Theme.accentFill(palettes.style) : negativeColor)
                            : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: Capsule())
                .frame(height: headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(yes ? String(localized: "Ja") : String(localized: "Nein"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(yes ? "check-today" : "decline-today")
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

    /// Die Uhrzeit des Habits — dieselbe Formatierung wie im Regel-Satz,
    /// damit „um 07:30" auf der Karte und im Editor gleich aussieht.
    private var timeText: String? { RecurrenceText.timeText(habit.timeMinutes) }
}

// MARK: – Das Halten-Menü

/// Das System-Kontextmenü für die Rasterkarte — dieselbe Anhebe-Mechanik
/// wie beim Halten auf einem Link: Karte hebt sich, große Vorschau, Menü
/// darunter, Tipp auf die Vorschau COMMITTET (öffnet Bearbeiten).
///
/// **Warum UIKit.** Zwei SwiftUI-Wege scheitern hier nacheinander:
/// `.onLongPressGesture` feuert in dieser Verschachtelung (List-Zelle,
/// horizontale ScrollView im Raster) schlicht nie, und `.contextMenu`
/// kennt keinen Vorschau-Tipp (`willPerformPreviewAction` hat kein
/// SwiftUI-Gegenstück). `UIContextMenuInteraction` ist exakt die Engine,
/// die auch Safari für Links benutzt.
///
/// **Wie es hängt.** Die unsichtbare Trägeransicht bekommt vom `background`
/// exakt den Kartenrahmen. Die Interaktion selbst hängt an der ZELLE (bzw.
/// dem ersten Scroll-Vorfahren): der eigene Wrapper ist nur ein GESCHWISTER
/// des Karteninhalts, durch ihn läuft keine Berührung (nachgemessen — die
/// Halten-Erkenner-Vorstufe am Wrapper hat nie gefeuert). Ausgelöst wird
/// nur über dem eigenen Rahmen; das Anheben ist per `visiblePath` exakt auf
/// die abgerundete Karte beschnitten.
private struct GraphMenuAction {
    let title: String
    let symbol: String
    let handler: () -> Void
}

private struct GraphContextMenu: UIViewRepresentable {
    let cardRadius: CGFloat
    let previewWidth: CGFloat
    let preview: () -> AnyView
    let actions: [GraphMenuAction]
    let commit: () -> Void

    func makeUIView(context: Context) -> MenuHost {
        MenuHost(cardRadius: cardRadius, previewWidth: previewWidth,
                 preview: preview, actions: actions, commit: commit)
    }

    func updateUIView(_ view: MenuHost, context: Context) {
        view.cardRadius = cardRadius
        view.previewWidth = previewWidth
        view.preview = preview
        view.actions = actions
        view.commit = commit
    }

    static func dismantleUIView(_ view: MenuHost, coordinator: ()) {
        view.detach()
    }

    final class MenuHost: UIView, UIContextMenuInteractionDelegate {
        var cardRadius: CGFloat
        var previewWidth: CGFloat
        var preview: () -> AnyView
        var actions: [GraphMenuAction]
        var commit: () -> Void
        private var interaction: UIContextMenuInteraction?
        private weak var host: UIView?

        init(cardRadius: CGFloat, previewWidth: CGFloat,
             preview: @escaping () -> AnyView,
             actions: [GraphMenuAction],
             commit: @escaping () -> Void) {
            self.cardRadius = cardRadius
            self.previewWidth = previewWidth
            self.preview = preview
            self.actions = actions
            self.commit = commit
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit { detach() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Zeilen-Recycling: raus aus dem Fenster -> Interaktion abhängen,
            // wieder rein -> neu anhängen (die Zelle kann eine andere sein).
            guard window != nil else { detach(); return }
            guard interaction == nil else { return }
            var ancestor = superview
            var container: UIView?
            while let view = ancestor {
                container = view
                if view is UICollectionViewCell || view is UITableViewCell
                    || view is UIScrollView { break }
                ancestor = view.superview
            }
            guard let container else { return }
            let interaction = UIContextMenuInteraction(delegate: self)
            container.addInteraction(interaction)
            self.interaction = interaction
            host = container
            trace("menu: attached to \(String(describing: type(of: container)))")
        }

        func detach() {
            if let interaction { host?.removeInteraction(interaction) }
            interaction = nil
            host = nil
        }

        // Ausgelöst wird nur ÜBER der Karte — der Kopf darüber bleibt frei
        // (er ist eine Werkzeugleiste, siehe `longPressSink`).
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint)
            -> UIContextMenuConfiguration? {
            guard let view = interaction.view else { return nil }
            let local = view.convert(location, to: self)
            trace("menu: config? loc=\(local) bounds=\(bounds)")
            guard bounds.contains(local) else { return nil }
            let width = previewWidth
            let makePreview = preview
            let actions = actions
            return UIContextMenuConfiguration(identifier: nil, previewProvider: {
                let controller = UIHostingController(rootView: makePreview())
                controller.view.backgroundColor = .clear
                controller.preferredContentSize = controller.sizeThatFits(
                    in: CGSize(width: width, height: 10_000))
                return controller
            }, actionProvider: { _ in
                UIMenu(children: actions.map { action in
                    UIAction(title: action.title,
                             image: UIImage(systemName: action.symbol)) { _ in
                        action.handler()
                    }
                })
            })
        }

        /// Der Tipp AUF die Vorschau — das Commit, wie das Öffnen eines
        /// gehaltenen Links. Erst nach der Abbau-Animation handeln, sonst
        /// kollidiert das Bearbeiten-Blatt mit dem zufahrenden Menü.
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionCommitAnimating) {
            let commit = commit
            animator.preferredCommitStyle = .dismiss
            animator.addCompletion { commit() }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration)
            -> UITargetedPreview? {
            targetedPreview(for: interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration)
            -> UITargetedPreview? {
            targetedPreview(for: interaction)
        }

        /// Angehoben wird NUR die Karte: der Schnappschuss der Zelle, per
        /// `visiblePath` auf die abgerundete Rasterfläche beschnitten.
        private func targetedPreview(for interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let container = interaction.view, window != nil else { return nil }
            let parameters = UIPreviewParameters()
            parameters.visiblePath = UIBezierPath(roundedRect: convert(bounds, to: container),
                                                  cornerRadius: cardRadius)
            return UITargetedPreview(view: container, parameters: parameters)
        }
    }
}
