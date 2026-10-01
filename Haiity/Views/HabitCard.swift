import SwiftUI
import ObjectiveC

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
            && a.showsMonthLabels == b.showsMonthLabels
            && a.leadingSwipe == b.leadingSwipe && a.trailingSwipe == b.trailingSwipe
            && a.calendar.timeZone.identifier == b.calendar.timeZone.identifier
    }

    let habit: Habit
    /// Zusammengezogener Kopf. Standard `false`, damit Vorschauen und Tests
    /// die Karte ohne Einstellungs-Kontext bauen können.
    var collapsed: Bool = false
    var showsMonthLabels: Bool = true
    /// Heute abhaken (Kopfzeile). Der einzige Weg von dieser Karte aus, der
    /// direkt schreibt — er sitzt auf einem beschrifteten Knopf.
    let onToggleDay: (String) -> Void
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
    var onDelete: () -> Void = {}
    var onCreateOneTime: () -> Void = {}
    var onEnableSorting: () -> Void = {}
    /// Heute mit Ja bzw. Nein beantworten (Habit-Art „Ja/Nein"). Umschaltend:
    /// dieselbe Antwort ein zweites Mal nimmt sie zurück. Steht mit einem
    /// Standardwert ganz am Ende, damit Vorschauen und Tests die Karte ohne
    /// diesen Weg bauen können.
    var onAnswer: (Bool) -> Void = { _ in }
    /// Die Wisch-Aktionen hinter der Karte — kartenhoch, selbst aufgezogen
    /// (die System-Wischknöpfe sind auf hohen Zeilen fixe Kapseln, siehe
    /// SwipeReveal). Erste Aktion je Seite = die feste; Voll-Wisch löst sie
    /// aus.
    var leadingSwipe: [RevealAction] = []
    var trailingSwipe: [RevealAction] = []
    var calendar: Calendar = .current

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.habitInlineSortingActive) private var habitInlineSortingActive
    /// Klammert Pille und verschmolzenen Zustand zusammen, damit das eine ins
    /// andere fliegt statt zu blinken.
    @Namespace private var doneNamespace
    private static let doneID = "done"
    /// Aufzieh-Zustand der Karte (semantisch: positiv = leading offen).
    /// Lebt in einer eigenen Sitzung, damit der Kopf und das Raster nicht
    /// bei jedem Pan-Frame mit der Karte neu gebaut werden.
    @State private var reveal = SwipeRevealSession()
    /// UIKit lifts the transparent bridge host, while the original SwiftUI
    /// surface would otherwise remain underneath and draw a second halo.
    @State private var isContextMenuVisible = false

    private var today: String { DayKey.today(calendar: calendar) }
    private var doneToday: Bool {
        GoalEngine.dayCounts(habit: habit, day: today, calendar: calendar)
    }
    private var declinedToday: Bool { habit.isDeclined(today) }
    /// Status controls follow the same palette as this habit's graph. The
    /// global palette remains the app tint; this keeps a custom habit color
    /// coherent without recoloring unrelated controls.
    private var habitStyle: PaletteStyle { palettes.style(for: habit) }

    private var statusBackground: Color {
        Theme.level(0, dark: scheme == .dark, palette: habitStyle)
    }

    /// Die Verneinungsfarbe DIESES Habits — dieselbe, die seine Zellen im
    /// Raster tragen. Der Kopf darf nicht in einer anderen Farbe „Nein"
    /// sagen als die Fläche darunter.
    private var negativeColor: Color {
        Theme.color(habitStyle.negative(dark: scheme == .dark))
    }

    /// Höhe der Kopfzeile. Ausgeklappt volle Trefferfläche, zusammengezogen
    /// deutlich flacher — der Kopf soll beim Scrollen nicht als leerer Kasten
    /// über dem Raster stehen bleiben. Als Frame-Höhe (nicht als
    /// Zeilen-Inset) gesetzt, damit der Wert im Übergang INTERPOLIERT.
    private var headerHeight: CGFloat { max(44, collapsed ? 32 : Theme.Metrics.hit) }

    /// Abstand Kopf -> eigenes Raster. Klein und absichtlich: der Kopf
    /// gehört zur Fläche DARUNTER.
    private var innerGap: CGFloat { collapsed ? 4 : Theme.Metrics.gap }

    /// Abstand zur nächsten Karte — immer ein Vielfaches des inneren
    /// Abstands, sonst liest sich der freistehende Kopf als Fußzeile der
    /// vorigen Karte statt als Überschrift der eigenen.
    private var outerGap: CGFloat { collapsed ? 8 : 12 }

    var body: some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("card.body")
        #endif
        return VStack(alignment: .leading, spacing: innerGap) {
            header
            revealingGrid
        }
        // Der Zug für das Aufziehen deckt die GANZE Zeile (Kopf + Karte):
        // vom Kopf aus gehen beide Seiten, über dem Raster entscheidet
        // `SwipeReveal.canBegin` (Historie vor Aufziehen, außer am Ende).
        .background {
            if habitInlineSortingActive {
                Color.clear.accessibilityHidden(true)
            } else {
                SwipeRevealPan(shouldBegin: revealShouldBegin,
                               began: { reveal.begin() },
                               changed: revealChanged,
                               ended: revealEnded,
                               cancelled: { snapReveal(to: 0) },
                               isOpen: { reveal.offset != 0 },
                               ownerID: habit.id)
            }
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
        .allowsHitTesting(!reveal.actionLock)
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDismissAll)) { _ in
            guard reveal.offset != 0 else { return }
            snapReveal(to: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDidBegin)) { note in
            guard let ownerID = note.object as? UUID, ownerID != habit.id,
                  reveal.offset != 0 else { return }
            snapReveal(to: 0)
        }
    }

    // MARK: – Aufziehen: kartenhohe Wisch-Knöpfe

    /// Karte über Knöpfen: die Knöpfe stehen HINTER der Karte in derselben
    /// Schachtel (und sind damit exakt kartenhoch); die Karte schiebt sich
    /// beim Ziehen zur Seite und legt sie frei. Der Kopf darüber bleibt
    /// stehen — die Knöpfe gehören zur Karte, nicht zur Zeile.
    private var revealingGrid: some View {
        HabitSlidingGrid(reveal: reveal,
                         leadingSwipe: leadingSwipe,
                         trailingSwipe: trailingSwipe,
                         layoutDirection: layoutDirection,
                         onClose: {
                             Theme.Haptics.select()
                             snapReveal(to: 0)
                         },
                         onAction: revealActionTapped) {
            grid
        }
    }

    private func revealShouldBegin(towardTrailing: Bool, horizontal: Bool,
                                   overGrid: Bool, gridAtTrailingEnd: Bool) -> Bool {
        SwipeReveal.canBegin(towardTrailing: towardTrailing,
                             horizontalIntent: horizontal,
                             open: reveal.offset != 0,
                             hasLeading: !leadingSwipe.isEmpty,
                             hasTrailing: !trailingSwipe.isEmpty,
                             overGrid: overGrid,
                             gridAtTrailingEnd: gridAtTrailingEnd)
    }

    private func revealChanged(_ translation: CGFloat) {
        reveal.applyTranslation(translation,
                                leadingCount: leadingSwipe.count,
                                trailingCount: trailingSwipe.count)
    }

    private func revealActionTapped(_ action: RevealAction) {
        guard !reveal.actionLock else { return }
        reveal.actionLock = true
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22), completionCriteria: .removed) {
            reveal.offset = 0
        } completion: {
            action.handler()
            reveal.actionLock = false
        }
    }

    private func revealEnded(_ translation: CGFloat, velocity: CGFloat) {
        let resting = SwipeReveal.resting(
            pull: reveal.start + translation, velocity: velocity,
            leadingWidth: SwipeReveal.revealWidth(count: leadingSwipe.count),
            trailingWidth: SwipeReveal.revealWidth(count: trailingSwipe.count),
            cardWidth: reveal.width)
        switch resting {
        case .closed:
            // Nur wenn wirklich etwas ZU ging, gibt es den Tick — ein
            // abgebrochener Mini-Zug ist kein Ereignis.
            if reveal.start != 0 { Theme.Haptics.select() }
            snapReveal(to: 0, velocity: velocity)
        case .leading:
            if reveal.start == 0 { Theme.Haptics.select() }
            snapReveal(to: SwipeReveal.revealWidth(count: leadingSwipe.count), velocity: velocity)
        case .trailing:
            if reveal.start == 0 { Theme.Haptics.select() }
            snapReveal(to: -SwipeReveal.revealWidth(count: trailingSwipe.count), velocity: velocity)
        case .commitLeading:
            commitReveal(leadingSwipe.first)
        case .commitTrailing:
            commitReveal(trailingSwipe.first)
        }
    }

    /// Voll-Wisch: die feste Erst-Aktion, mit Haptik — und die Karte
    /// schnappt zurück (die Aktion zeigt sich selbst: Pille, Toast, Raster).
    private func commitReveal(_ action: RevealAction?) {
        Theme.Haptics.check()
        if let action { revealActionTapped(action) }
    }

    private func snapReveal(to target: CGFloat, velocity: CGFloat = 0) {
        guard abs(target - reveal.offset) > 0.5 else { return }
        if let animation = SwipeRevealMotion.settleAnimation(
            reduceMotion: reduceMotion,
            velocity: velocity,
            distance: target - reveal.offset) {
            withAnimation(animation) {
                reveal.offset = target
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                reveal.offset = target
            }
        }
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
    /// A tap opens history; horizontal drags continue to scroll the graph.
    private var grid: some View {
        // `.equatable()` ist Tempo, nicht Kosmetik (dasselbe Muster wie die
        // Mehr-Liste in `MorePanelSurface`): ohne den Vergleich baut jede
        // Auswertung dieser Karte die 371 Zellen neu, auch wenn sich nur das
        // Chrom bewegt hat. Store-Änderungen kommen an — sie ändern `habit`.
            ContributionGrid(habit: habit,
                             weeks: gridWeeks,
                             showsMonthLabels: showsMonthLabels,
                             calendar: calendar)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isContextMenuVisible ? 0 : 1)
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
            .overlay {
                GraphContextMenu(cardRadius: Theme.Metrics.cardRadius,
                                 previewWidth: previewWidth,
                                 previewHeight: Self.contextPreviewHeight,
                                 previewOwnsSurface: true,
                                 previewAccessibilityIdentifier: "habit-preview",
                                 preview: { AnyView(habitPreview) },
                                 actions: menuActions,
                                 commit: onEdit,
                                 onMenuVisibilityChanged: { visible in
                                     if visible {
                                         reveal.offset = 0
                                         reveal.start = 0
                                     }
                                     isContextMenuVisible = visible
                                 })
                    .frame(maxWidth: previewWidth)
                    .allowsHitTesting(!habitInlineSortingActive)
            }
            .onTapGesture {
                onBackfill()
            }
            .accessibilityAction(named: String(localized: "Historie"), onBackfill)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("habit-history")
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
    /// A context-menu preview is hosted outside the list's layout tree. Keep
    /// its vertical proposal stable so UIKit cannot collapse the graph to the
    /// action row while SwiftUI is still measuring it.
    static let contextPreviewHeight: CGFloat = 160
    /// Rand zwischen Vorschau und Bildschirmkante.
    static let previewMargin: CGFloat = 16
    /// Untergrenze für sehr schmale Fenster (Slide-Over).
    static let previewMinWidth: CGFloat = 260

    /// Breite des AKTIVEN Fensters, nicht `UIScreen.main.bounds`: das ist
    /// die Größe des Bildschirms, nicht die der App — im Split View auf dem
    /// iPad wäre die Vorschau damit breiter als das Fenster, in dem sie
    /// steht. Nur wenn gar keine Szene erreichbar ist, fällt es auf den
    /// Bildschirm zurück.
    static func windowWidth() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let width = scene?.keyWindow?.bounds.width, width.isFinite, width > 0 {
            return width
        }
        if let width = scene?.screen.bounds.width, width.isFinite, width > 0 {
            return width
        }
        let fallback = UIScreen.main.bounds.width
        return fallback.isFinite && fallback > 0 ? fallback : 375
    }

    /// Breite und Wochenzahl der Vorschau aus der FENSTERBREITE. Als reine
    /// Funktion, weil sie auf einem SE (375 pt) und auf einem Max (440 pt)
    /// stimmen muss und ein Screenshot je Gerät keine Prüfung ist.
    ///
    /// Die Wochenzahl fällt aus der Breite: Innenmaß geteilt durch das
    /// Rastermaß (Zelle + Lücke). Mehr als 53 gibt es nicht — das Raster IST
    /// ein Jahr.
    static func previewMetrics(windowWidth: CGFloat) -> (width: CGFloat, weeks: Int) {
        let finiteWindowWidth = windowWidth.isFinite && windowWidth > 0
            ? windowWidth : 375
        let width = max(previewMinWidth, finiteWindowWidth - 2 * previewMargin)
        let content = width - 2 * Theme.Metrics.gutter
        let pitch = previewCell + previewGap
        let weeks = min(53, max(8, Int((content + previewGap) / pitch)))
        return (width, weeks)
    }

    private var previewWidth: CGFloat { Self.previewMetrics(windowWidth: Self.windowWidth()).width }
    private var gridWeeks: Int {
        GridCalendar.weeksForDisplay(habit: habit,
                                     today: today,
                                     minimumWeeks: 24,
                                     maximumWeeks: 53,
                                     calendar: calendar)
    }
    private static let previewGraphGap: CGFloat = 2

    private var previewGraphCellSize: CGFloat {
        let weeks = CGFloat(max(gridWeeks, 1))
        let contentWidth = max(1, previewWidth - 2 * Theme.Metrics.gutter)
        let gap = Self.previewGraphGap
        return max(2, (contentWidth + gap) / weeks - gap)
    }

    private var habitPreview: some View {
        let snapshot = GridCalendar.snapshot(habit: habit,
                                             weeks: gridWeeks,
                                             today: today,
                                             calendar: calendar)
        let streak = habit.streak(today: today, calendar: calendar)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if !habit.emoji.isEmpty {
                    Text(habit.emoji)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent(habitStyle).opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: CornerRadius.chip,
                                                         style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(String(localized: "Verlauf"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                previewMetric(value: snapshot.filledCount,
                              label: String(localized: "Tage"))
                if streak > 0 {
                    previewMetric(value: streak,
                                  label: String(localized: "Serie"),
                                  symbol: "flame.fill")
                }
            }
            ContributionGrid(habit: habit,
                             weeks: gridWeeks,
                             cellSize: previewGraphCellSize,
                             gap: Self.previewGraphGap,
                             interactive: false,
                             showsMonthLabels: false,
                             calendar: calendar)
                .equatable()
        }
        .padding(14)
        .frame(width: previewWidth)
        .appSurface()
        // Die Vorschau ist eine EIGENE Präsentation und erbt die Umgebung
        // der Zeile nicht: ohne diese Zeile fiel das Raster darin auf die
        // Standardpalette zurück und leuchtete grün, während dieselben
        // Zellen zwei Millimeter daneben blau sind.
        .environment(\.palettes, palettes)
        .environment(\.appearancePreferences, appearancePreferences)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habit-preview")
    }

    private func previewMetric(value: Int,
                               label: String,
                               symbol: String? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.semibold))
                }
                Text(verbatim: "\(value)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(symbol == "flame.fill" ? .orange : .primary)
        .accessibilityElement(children: .combine)
    }

    /// Die Einträge UNTER der System-Vorschau. Was über den langen Druck
    /// erreichbar ist, bleibt inhaltlich dasselbe wie zuvor im Blatt:
    /// Nacharbeiten, Session, Bearbeiten, Archivieren, Teilen.
    private var menuActions: [GraphMenuAction] {
        var secondary = [
            // Session: „ich mache das JETZT" — startet die Live-Aktivität.
            GraphMenuAction(title: String(localized: "Session starten"),
                            symbol: "timer",
                            handler: { HabitSessionManager.shared.start(habit: habit) })]
        if habit.recurrence.frequency != .once {
            secondary.append(GraphMenuAction(title: String(localized: "Einmalig anlegen"),
                                              symbol: "plus.square",
                                              handler: onCreateOneTime))
        }
        secondary += [
            GraphMenuAction(title: String(localized: "Rückgängig"),
                            symbol: "arrow.uturn.backward",
                            handler: onClear),
            GraphMenuAction(title: String(localized: "Archivieren"),
                            symbol: "archivebox",
                            handler: onArchive),
            GraphMenuAction(title: String(localized: "Löschen"),
                            symbol: "trash",
                            handler: onDelete,
                            destructive: true),
            GraphMenuAction(title: String(localized: "Sortieren"),
                            symbol: "arrow.up.arrow.down",
                            handler: onEnableSorting),
            GraphMenuAction(title: String(localized: "Als Bild teilen"),
                            symbol: "square.and.arrow.up",
                            handler: shareCard)]
        return [
            GraphMenuAction(title: String(localized: "Nacharbeiten"),
                            symbol: "calendar.badge.plus",
                            handler: onBackfill),
            GraphMenuAction(title: String(localized: "Bearbeiten"),
                            symbol: "pencil",
                            handler: onEdit),
            GraphMenuAction(title: String(localized: "Mehr"),
                            symbol: "ellipsis.circle",
                            handler: {},
                            submenu: secondary)]
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
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                    nameRun
                    HStack(spacing: Theme.Metrics.gap) {
                        Spacer(minLength: 0)
                        todayButton
                    }
                }
                .padding(.horizontal, 4)
            } else {
                HStack(spacing: Theme.Metrics.gap) {
                    nameRun
                    Spacer(minLength: Theme.Metrics.gap)
                    // Zusammengezogen bleibt der Name mit verschmolzenem
                    // Heute-Zustand.
                    if !collapsed { todayButton }
                }
                .frame(minHeight: headerHeight)
                // Auf die Innenkante der Rasterfläche ausgerichtet: Name und
                // erste Rasterspalte stehen in EINER Flucht.
                .padding(.horizontal, 4)
            }
        }
    }

    // Hier stand der Kopf-„Schlucker" (ein LongPressGesture hinter dem
    // Kopf). Er stammt aus der Zeit, in der das Halten-Menü selbst eine
    // SwiftUI-Geste am Raster war und der Kopf sie fernhalten musste. Das
    // Menü prüft seinen Ort inzwischen SELBST (GraphContextMenu, nur über
    // der Karte) — und die tote SwiftUI-Geste hat obendrein den
    // Aufzieh-Zug vom Kopf ferngehalten (nachgemessen: Züge, die auf dem
    // Kopf begannen, erreichten den Zellen-Pan nie).

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

    @ViewBuilder
    private var nameContent: some View {
        Group {
            if typeSize.isAccessibilitySize && !collapsed {
                VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !habit.emoji.isEmpty {
                            Text(habit.emoji)
                                .font(.title3)
                        }
                        Text(habit.name)
                            .font(.headline)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    meta
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !habit.emoji.isEmpty {
                        Text(habit.emoji)
                            .font(collapsed ? .subheadline : .title3)
                    }
                    Text(habit.name)
                        .font(collapsed ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : (collapsed ? 1 : 2))
                    // Der Zustand steht HINTER dem Namen, nicht davor: sonst rückt
                    // ein Häkchen die Namen der abgehakten Karten ein und die Liste
                    // fluchtet nicht mehr.
                    if collapsed { mergedDone }
                    if !collapsed { meta.fixedSize() }
                }
            }
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
                                 ? AnyShapeStyle(Theme.accentText(habitStyle))
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
                                    ? AnyShapeStyle(Theme.accentText(habitStyle))
                                    : AnyShapeStyle(HierarchicalShapeStyle.tertiary)))
                .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
        }
    }

    private var collapsedActionLabel: String {
        switch habit.kind {
        case .quantity:
            return String(localized: "Heute: \(habit.log[today] ?? 0) von \(habit.recurrence.effectiveTarget)")
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
        let streak = habit.streak(today: today, calendar: calendar)
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
        guard !GoalEngine.isScheduled(habit: habit, day: today, calendar: calendar) else { return nil }
        guard let next = habit.recurrence.nextOccurrence(after: today, calendar: calendar),
              let date = DayKey.date(from: next, calendar: calendar) else {
            return (String(localized: "frei"), String(localized: "keiner mehr"))
        }
        let weekday = calendar.component(.weekday, from: date)
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
            let target = habit.recurrence.effectiveTarget
            let value = habit.log[today] ?? 0
            Button {
                Theme.Haptics.check()
                onIncrement()
            } label: {
                pill("+ \(value)/\(target)", monospaced: true)
            }
            .buttonStyle(.plain)
            // KEIN eigenes Kontextmenü mehr: der lange Druck gehört der
            // ganzen Zeile. Zwei verschachtelte Menüs auf derselben Karte
            // hießen, dass ein langer Druck je nach getroffenem Pixel etwas
            // anderes tut. „Rückgängig" steht im Zeilenmenü.
            .accessibilityLabel(String(localized: "Heute: \(value) von \(target)"))
            .accessibilityHint(String(localized: "Erhöht den Zähler um eins."))
            .accessibilityIdentifier("check-today")
        case .yesNo:
            answerButtons
        case .checkbox:
            Button {
                Theme.Haptics.check()
                onToggleDay(today)
            } label: {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(doneToday
                        ? AnyShapeStyle(Theme.accentText(habitStyle))
                        : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneToday
                                ? String(localized: "✓ Erledigt")
                                : String(localized: "Heute"))
            .accessibilityIdentifier("check-today")
            .accessibilityHint(doneToday
                ? String(localized: "Macht den heutigen Eintrag rückgängig.")
                : String(localized: "Markiert den heutigen Tag als erledigt."))
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
                            ? AnyShapeStyle(yes ? Theme.accentFill(habitStyle) : negativeColor)
                            : AnyShapeStyle(statusBackground),
                            in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
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
            .background(doneToday ? Theme.accentFill(habitStyle) : statusBackground,
                        in: Capsule())
            .foregroundStyle(doneToday ? .white : .primary)
            .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
            .frame(minHeight: headerHeight)
            .contentShape(Rectangle())
    }

    /// Die Uhrzeit des Habits — dieselbe Formatierung wie im Regel-Satz,
    /// damit „um 07:30" auf der Karte und im Editor gleich aussieht.
    private var timeText: String? { RecurrenceText.timeText(habit.timeMinutes) }
}

/// Isolates the reveal offset from the habit header. The pan still lives on
/// the full row; only this layer reads `offset` on each drag frame.
private struct HabitSlidingGrid<Grid: View>: View {
    var reveal: SwipeRevealSession
    let leadingSwipe: [RevealAction]
    let trailingSwipe: [RevealAction]
    let layoutDirection: LayoutDirection
    let onClose: () -> Void
    let onAction: (RevealAction) -> Void
    @ViewBuilder var grid: () -> Grid

    private var revealOffset: CGFloat { reveal.offset }
    private var mirror: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }

    var body: some View {
        ZStack {
            grid()
                .offset(x: revealOffset * mirror)
                .zIndex(1)
                .accessibilityHidden(revealOffset != 0)
                .overlay {
                    if revealOffset != 0 {
                        Color.clear
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                           style: .continuous))
                            .onTapGesture(perform: onClose)
                            .offset(x: revealOffset * mirror)
                    }
                }
            SwipeRevealActions(actions: leadingSwipe,
                               alignment: .leading,
                               exposedWidth: max(revealOffset, 0),
                               height: nil,
                               onAction: onAction)
                .allowsHitTesting(revealOffset > 0)
            SwipeRevealActions(actions: trailingSwipe,
                               alignment: .trailing,
                               exposedWidth: max(-revealOffset, 0),
                               height: nil,
                               onAction: onAction)
                .allowsHitTesting(revealOffset < 0)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            reveal.width = width
        }
        .accessibilityRevealActions(leadingSwipe + trailingSwipe)
    }
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
/// **Wie es hängt.** UIKit darf die Interaktion nicht an einer gemeinsamen
/// Tabellenzelle besitzen: eine Stats-Zeile enthält mehrere Karten, und UIKit
/// würde beim Anheben der Zelle alle Geschwister mitnehmen. Jeder Bridge-Host
/// besitzt deshalb genau eine eigene Interaktion.
struct GraphMenuAction {
    let title: String
    let symbol: String
    let handler: () -> Void
    var destructive: Bool = false
    var submenu: [GraphMenuAction]? = nil
}

struct GraphContextMenu: UIViewRepresentable {
    let cardRadius: CGFloat
    let previewWidth: CGFloat
    let previewHeight: CGFloat
    var previewOwnsSurface = false
    var previewAccessibilityIdentifier: String? = nil
    let preview: () -> AnyView
    let actions: [GraphMenuAction]
    let commit: () -> Void
    /// A short tap has no context-menu callback. Ranking rows opt in so that
    /// tap runs `commit`; every other card keeps the long-press menu only.
    var performsCommitOnTap = false
    var onMenuVisibilityChanged: (Bool) -> Void = { _ in }
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var appearancePreferences

    /// SwiftUI can propose an unbounded size to an overlay inside a
    /// horizontal ScrollView. UIKit cannot represent that as a view frame;
    /// keep the bridge finite while preserving any real parent proposal.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MenuHost,
                      context: Context) -> CGSize? {
        let fallbackWidth = Self.finite(uiView.previewWidth, fallback: 320)
        let fallbackHeight = Self.finite(uiView.previewHeight, fallback: 1)
        let width = proposal.width.map { Self.finite($0, fallback: fallbackWidth) }
            ?? fallbackWidth
        let height = proposal.height.map { Self.finite($0, fallback: fallbackHeight) }
            ?? fallbackHeight
        return CGSize(width: width, height: height)
    }

    private static func finite(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : fallback
    }

    func makeUIView(context: Context) -> MenuHost {
        MenuHost(cardRadius: cardRadius, previewWidth: previewWidth,
                 previewHeight: previewHeight,
                 previewOwnsSurface: previewOwnsSurface,
                 previewAccessibilityIdentifier: previewAccessibilityIdentifier,
                 preview: preview, actions: actions, commit: commit,
                 performsCommitOnTap: performsCommitOnTap,
                 palettes: palettes,
                 appearancePreferences: appearancePreferences,
                 onMenuVisibilityChanged: onMenuVisibilityChanged)
    }

    func updateUIView(_ view: MenuHost, context: Context) {
        view.cardRadius = cardRadius
        view.previewWidth = previewWidth
        view.previewHeight = previewHeight
        view.previewOwnsSurface = previewOwnsSurface
        view.previewAccessibilityIdentifier = previewAccessibilityIdentifier
        view.preview = preview
        view.actions = actions
        view.commit = commit
        view.performsCommitOnTap = performsCommitOnTap
        view.palettes = palettes
        view.appearancePreferences = appearancePreferences
        view.onMenuVisibilityChanged = onMenuVisibilityChanged
    }

    static func dismantleUIView(_ view: MenuHost, coordinator: ()) {
        view.detach()
    }

    final class MenuHost: UIView, UIContextMenuInteractionDelegate {
        var cardRadius: CGFloat
        var previewWidth: CGFloat
        var previewHeight: CGFloat
        var previewOwnsSurface: Bool
        var previewAccessibilityIdentifier: String?
        var preview: () -> AnyView
        var actions: [GraphMenuAction]
        var commit: () -> Void
        var performsCommitOnTap: Bool
        var palettes: PaletteBook
        var appearancePreferences: AppearancePreferences
        var onMenuVisibilityChanged: (Bool) -> Void
        fileprivate let identifier = UUID().uuidString
        private lazy var interaction = UIContextMenuInteraction(delegate: self)
        private var menuVisible = false

        init(cardRadius: CGFloat, previewWidth: CGFloat,
             previewHeight: CGFloat,
             previewOwnsSurface: Bool,
             previewAccessibilityIdentifier: String?,
             preview: @escaping () -> AnyView,
             actions: [GraphMenuAction],
             commit: @escaping () -> Void,
             performsCommitOnTap: Bool = false,
             palettes: PaletteBook,
             appearancePreferences: AppearancePreferences,
             onMenuVisibilityChanged: @escaping (Bool) -> Void) {
            self.cardRadius = cardRadius
            self.previewWidth = previewWidth
            self.previewHeight = previewHeight
            self.previewOwnsSurface = previewOwnsSurface
            self.previewAccessibilityIdentifier = previewAccessibilityIdentifier
            self.preview = preview
            self.actions = actions
            self.commit = commit
            self.performsCommitOnTap = performsCommitOnTap
            self.palettes = palettes
            self.appearancePreferences = appearancePreferences
            self.onMenuVisibilityChanged = onMenuVisibilityChanged
            super.init(frame: .zero)
            isUserInteractionEnabled = true
            isHidden = false
            addInteraction(interaction)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        /// A representable inside a horizontally scrolling SwiftUI subtree
        /// can still receive an invalid frame after `sizeThatFits`. Clamp at
        /// the UIKit boundary so Core Animation never sees NaN or infinity.
        override var frame: CGRect {
            get { super.frame }
            set {
                let fallbackWidth = GraphContextMenu.finite(previewWidth, fallback: 320)
                let fallbackHeight = GraphContextMenu.finite(previewHeight, fallback: 1)
                let origin = CGPoint(x: newValue.origin.x.isFinite ? newValue.origin.x : 0,
                                     y: newValue.origin.y.isFinite ? newValue.origin.y : 0)
                let size = CGSize(width: newValue.size.width.isFinite
                                  ? max(0, newValue.size.width) : fallbackWidth,
                                  height: newValue.size.height.isFinite
                                  ? max(0, newValue.size.height) : fallbackHeight)
                super.frame = CGRect(origin: origin, size: size)
            }
        }

        func detach() {
            setMenuVisible(false)
            if interactions.contains(where: { $0 === interaction }) {
                removeInteraction(interaction)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            guard performsCommitOnTap, !menuVisible, let touch = touches.first else { return }
            guard bounds.contains(touch.location(in: self)) else { return }
            commit()
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint)
            -> UIContextMenuConfiguration? {
            guard bounds.contains(location) else { return nil }
            setMenuVisible(true)
            let width = GraphContextMenu.finite(previewWidth, fallback: 320)
            let height = GraphContextMenu.finite(previewHeight, fallback: 1)
            let makePreview = preview
            let actions = actions
            let radius = cardRadius
            let ownsSurface = previewOwnsSurface
            let previewAccessibilityIdentifier = previewAccessibilityIdentifier
            let palettes = palettes
            let appearancePreferences = appearancePreferences
            return UIContextMenuConfiguration(identifier: identifier as NSString,
                                               previewProvider: {
                let root = AnyView(makePreview()
                    .frame(width: width, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.palettes, palettes)
                    .environment(\.appearancePreferences, appearancePreferences))
                let surfaced = ownsSurface
                    ? root
                    : AnyView(root.appSurface(cornerRadius: radius))
                let controller = RoundedPreviewHostingController(rootView: surfaced,
                                                                  radius: radius)
                controller.view.backgroundColor = .clear
                // SwiftUI's identifier stays inside the hosted tree, which
                // UIKit context-menu previews do not always expose. Mirror
                // the caller's identifier on the host so the lifted card has
                // one stable boundary for VoiceOver and UI tests.
                if let previewAccessibilityIdentifier {
                    controller.view.isAccessibilityElement = true
                    controller.view.accessibilityIdentifier = previewAccessibilityIdentifier
                    controller.view.accessibilityLabel = String(localized: "Vorschau")
                }
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                let measuredHeight = controller.sizeThatFits(
                    in: CGSize(width: width,
                               height: UIView.layoutFittingExpandedSize.height)).height
                let contentHeight = measuredHeight.isFinite && measuredHeight > 0
                    ? ceil(measuredHeight) : height
                let size = CGSize(width: width, height: contentHeight)
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.bounds = CGRect(origin: .zero, size: size)
                controller.preferredContentSize = size
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                return controller
            }, actionProvider: { _ in
                UIMenu(children: actions.map { self.menuElement(for: $0) })
            })
        }

        private func menuElement(for action: GraphMenuAction) -> UIMenuElement {
            if let submenu = action.submenu {
                return UIMenu(title: action.title,
                              image: UIImage(systemName: action.symbol),
                              children: submenu.map { menuElement(for: $0) })
            }
            let item = UIAction(title: action.title,
                                image: UIImage(systemName: action.symbol)) { _ in
                action.handler()
            }
            if action.destructive { item.attributes = [.destructive] }
            return item
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionAnimating?) {
            setMenuVisible(true)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willEndFor configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionAnimating?) {
            setMenuVisible(false)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionCommitAnimating) {
            animator.preferredCommitStyle = .dismiss
            // Start presenting the editor with the dismissal animation. Waiting
            // for UIKit's completion makes the preview tap feel unresponsive.
            commit()
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration)
            -> UITargetedPreview? {
            targetedPreview()
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration)
            -> UITargetedPreview? {
            targetedPreview()
        }

        private func targetedPreview() -> UITargetedPreview? {
            guard window != nil else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            let cardPath = UIBezierPath(roundedRect: bounds,
                                         cornerRadius: cardRadius)
            parameters.visiblePath = cardPath
            parameters.shadowPath = cardPath
            return UITargetedPreview(view: self, parameters: parameters)
        }

        private func setMenuVisible(_ visible: Bool) {
            guard menuVisible != visible else { return }
            menuVisible = visible
            onMenuVisibilityChanged(visible)
        }

    }
}

/// UIKit may relayout a context-menu preview after the initial size pass. The
/// host reapplies the same mask on every layout so the lifted card cannot
/// expose a larger rectangular shadow or lose its rounded silhouette.
private final class RoundedPreviewHostingController: UIHostingController<AnyView> {
        private let cardRadius: CGFloat

    init(rootView: AnyView, radius: CGFloat) {
        self.cardRadius = radius
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.cornerRadius = cardRadius
        view.layer.masksToBounds = true
        view.clipsToBounds = true
    }
}

// MARK: – Wisch-Aktionen (Daten)

/// Eine kartenhohe Wisch-Aktion. `Equatable` über das SICHTBARE (Titel,
/// Zeichen, Operation) — der Handler ist Verhalten und bei jedem Aufbau
/// frisch.
struct RevealAction: Identifiable, Equatable {
    let operation: SwipeOperation
    let title: String
    let symbol: String
    let tint: Color
    let handler: () -> Void

    var id: String { operation.rawValue }

    static func == (a: RevealAction, b: RevealAction) -> Bool {
        a.operation == b.operation && a.title == b.title && a.symbol == b.symbol
    }
}

extension View {
    /// VoiceOver kann die eigene Aufzieh-Geste nicht ausführen — jede
    /// Wisch-Aktion steht deshalb als benannte Aktion an der Karte.
    @ViewBuilder
    func accessibilityRevealActions(_ actions: [RevealAction]) -> some View {
        if actions.isEmpty {
            self
        } else {
            accessibilityActions {
                ForEach(actions) { action in
                    Button(action.title) { action.handler() }
                }
            }
        }
    }
}
