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
    private enum GraphPreviewAction {
        case backfill, session, edit, archive
    }

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
    @State private var showingGraphPreview = false
    @State private var graphPreviewAction: GraphPreviewAction?
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
            // UIKit-Erkenner statt `.onLongPressGesture`: der SwiftUI-Lang-
            // druck feuert in dieser Verschachtelung (List-Zelle, horizontale
            // ScrollView im Raster) schlicht NIE — vom Gerät gemeldet und im
            // Simulator reproduziert; dieselbe Erkenntnis steht seit v13 an
            // `GridTap` („SpatialTapGesture feuert hier nicht"). Ein
            // UILongPressGestureRecognizer am Container arbeitet mit dem
            // Scroll-Pan zusammen, statt gegen ihn zu verlieren.
            .background {
                HoldRecognizer {
                    Theme.Haptics.check()
                    showingGraphPreview = true
                }
            }
            .sheet(isPresented: $showingGraphPreview,
                   onDismiss: performGraphPreviewAction) {
                graphPreviewSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            #if DEBUG
            .onAppear { claimDebugPreviewIfRequested() }
            #endif
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

    private var graphPreviewSheet: some View {
        VStack(spacing: Theme.Metrics.gutter) {
            // KEIN Button: die Vorschau enthält (im Raster) einen
            // horizontalen ScrollView, der Tipps frisst, bevor sie einen
            // umgebenden Knopf erreichen — und ein Button, dessen ganzes
            // Label die Treffer abgibt (`allowsHitTesting(false)`), hat am
            // Gerät gar keine Tipp-Fläche mehr (beides „Tippen auf den
            // großen Graphen tut nichts", vom Gerät gemeldet). Deshalb eine
            // EIGENE Trefferschicht VOR der Vorschau: sie gewinnt jeden
            // Treffer, ihr Tipp-Erkenner hängt an keiner Knopf-Semantik.
            ZStack {
                habitPreview
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { requestGraphPreviewAction(.edit) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(String(localized: "Bearbeiten"))
            .accessibilityIdentifier("edit-habit-preview")

            Divider()
            Menu {
                habitActions
            } label: {
                Label(String(localized: "Weitere Aktionen"), systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, Theme.Metrics.gutter)
        .environment(\.palettes, palettes)
    }

    /// Die Aktionen UNTER der Vorschau. Sie tragen dieselben Kennungen wie
    /// die Knöpfe auf der Karte (`check-today`, `edit-habit`) — was über den
    /// langen Druck erreichbar ist, muss unter demselben Namen erreichbar
    /// sein wie direkt auf der Zeile.
    @ViewBuilder
    private var habitActions: some View {
        Button { requestGraphPreviewAction(.backfill) } label: {
            Label(String(localized: "Nacharbeiten"), systemImage: "calendar.badge.plus")
        }
        .accessibilityIdentifier("backfill-habit")
        // Session: „ich mache das JETZT" — startet die Live-Aktivität mit
        // laufender Zeit (und Fortschritt gegen die geplante Dauer, wenn es
        // eine gibt). Beendet wird auf der Aktivität selbst; deren
        // Fertig-Knopf hakt den Tag über denselben Trichter ab wie alles
        // andere. Direkt am Manager statt als Closure aus ContentView — die
        // Session hat keinen UI-Zustand, den die Liste kennen müsste.
        Button { requestGraphPreviewAction(.session) } label: {
            Label(String(localized: "Session starten"), systemImage: "timer")
        }
        .accessibilityIdentifier("start-session")
        Button { requestGraphPreviewAction(.edit) } label: {
            Label(String(localized: "Bearbeiten"), systemImage: "pencil")
        }
        .accessibilityIdentifier("edit-habit")
        Button { requestGraphPreviewAction(.archive) } label: {
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

    #if DEBUG
    /// Nur Debug: `-open-graph-preview` öffnet die Vorschau der ERSTEN
    /// erscheinenden Karte. Der lange Druck ist mit synthetischer Eingabe im
    /// Simulator nicht auslösbar — ohne diesen Haken wäre der
    /// Tipp-auf-Vorschau-Pfad (die ScrollView-Treffer-Falle!) unprüfbar.
    private static var debugPreviewClaimed = false

    private func claimDebugPreviewIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-open-graph-preview"),
              !Self.debugPreviewClaimed else { return }
        Self.debugPreviewClaimed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showingGraphPreview = true
        }
    }
    #endif

    private func requestGraphPreviewAction(_ action: GraphPreviewAction) {
        graphPreviewAction = action
        showingGraphPreview = false
    }

    private func performGraphPreviewAction() {
        guard let action = graphPreviewAction else { return }
        graphPreviewAction = nil
        switch action {
        case .backfill: onBackfill()
        case .session: HabitSessionManager.shared.start(habit: habit)
        case .edit: onEdit()
        case .archive: onArchive()
        }
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

// MARK: – Der Halten-Erkenner

/// Ein UIKit-Langdruck für die Rasterkarte.
///
/// **Warum UIKit.** `.onLongPressGesture` am Karten-Container feuert in
/// dieser Verschachtelung — List-Zelle, darin eine horizontale ScrollView —
/// schlicht nie (Gerät + Simulator; für Tipp-Gesten dokumentiert `GridTap`
/// seit v13 dasselbe). Ein `UILongPressGestureRecognizer` ist der Mechanismus,
/// mit dem UIKit-Apps genau das bauen (Halten auf Fotos-Raster im Scroller):
/// er läuft per Delegat GLEICHZEITIG mit dem Scroll-Pan und bricht sauber ab,
/// sobald der Finger zieht.
///
/// **Wie er hängt.** Die unsichtbare Trägeransicht bekommt vom `background`
/// exakt den Rahmen der Karte. Der Erkenner selbst hängt am SwiftUI-Container
/// darüber (nur dort kommen alle Berührungen vorbei) — gehandelt wird aber
/// NUR, wenn der Druck innerhalb des eigenen Rahmens liegt. So können viele
/// Karten im selben Container je ihren eigenen Erkenner tragen, ohne sich
/// gegenseitig auszulösen, und der Kopf über der Karte bleibt frei.
private struct HoldRecognizer: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> HoldView { HoldView(action: action) }

    func updateUIView(_ view: HoldView, context: Context) {
        view.action = action
    }

    static func dismantleUIView(_ view: HoldView, coordinator: ()) {
        view.detach()
    }

    final class HoldView: UIView, UIGestureRecognizerDelegate {
        var action: () -> Void
        private var recognizer: UILongPressGestureRecognizer?
        private weak var host: UIView?

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit { detach() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Zeilen-Recycling: raus aus dem Fenster -> Erkenner abhängen,
            // wieder rein -> neu anhängen (der Container kann ein anderer sein).
            guard window != nil else { detach(); return }
            guard recognizer == nil else { return }
            // Der eigene Wrapper ist ein GESCHWISTER des Karteninhalts —
            // Berührungen auf der Karte laufen nie durch ihn (nachgemessen:
            // der Erkenner am Wrapper hat nie gefeuert). Er muss an einen
            // echten VORFAHREN. Die vertikale Liste (erster UIScrollView
            // über uns) ist Vorfahre JEDER Karte; der Rahmen-Wächter in
            // `fired` sorgt dafür, dass nur die gehaltene Karte reagiert.
            var ancestor = superview
            var container: UIView?
            while let view = ancestor {
                container = view
                if view is UIScrollView { break }
                ancestor = view.superview
            }
            guard let container else { return }
            let r = UILongPressGestureRecognizer(target: self, action: #selector(fired))
            r.minimumPressDuration = 0.45
            r.cancelsTouchesInView = false
            r.delegate = self
            container.addGestureRecognizer(r)
            recognizer = r
            host = container
            trace("hold: attached to \(String(describing: type(of: container))) frame=\(frame)")
        }

        func detach() {
            if let recognizer { host?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            host = nil
        }

        @objc private func fired(_ r: UILongPressGestureRecognizer) {
            trace("hold: fired state=\(r.state.rawValue) loc=\(r.location(in: self)) bounds=\(bounds)")
            guard r.state == .began else { return }
            // Der Erkenner sieht den GANZEN Container — gehandelt wird nur
            // über der eigenen Karte.
            guard bounds.contains(r.location(in: self)) else { return }
            action()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
