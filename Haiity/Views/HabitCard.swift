import SwiftUI
import ObjectiveC

/// The name opens details; the graph keeps direct access to full history.
/// Today remains an independent control even with the compact preference.
/// Equality skips unchanged cards during parent chrome and toast updates.
struct HabitCard: View, Equatable {
    static func == (a: HabitCard, b: HabitCard) -> Bool {
        a.habit == b.habit && a.collapsed == b.collapsed
            && a.showsMonthLabels == b.showsMonthLabels
            && a.leadingSwipe == b.leadingSwipe && a.trailingSwipe == b.trailingSwipe
            && a.calendar == b.calendar
            && DayKey.key(for: a.now, calendar: a.calendar) == DayKey.key(for: b.now, calendar: b.calendar)
            && (a.onDetails == nil) == (b.onDetails == nil)
    }

    let habit: Habit
    /// Zusammengezogener Kopf. Standard `false`, damit Vorschauen und Tests
    /// die Karte ohne Einstellungs-Kontext bauen können.
    var collapsed: Bool = false
    var showsMonthLabels: Bool = true
    /// Heute abhaken (Kopfzeile). Der einzige Weg von dieser Karte aus, der
    /// direkt schreibt — er sitzt auf einem beschrifteten Knopf.
    let onToggleDay: (String) -> Void
    /// Open the existing history editor from the graph or context menu.
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
    var now: Date = .now
    var onDetails: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }
    /// Aufzieh-Zustand der Karte (semantisch: positiv = leading offen).
    /// Lebt in einer eigenen Sitzung, damit der Kopf und das Raster nicht
    /// bei jedem Pan-Frame mit der Karte neu gebaut werden.
    @State private var reveal = SwipeRevealSession()
    /// UIKit lifts the transparent bridge host, while the original SwiftUI
    /// surface would otherwise remain underneath and draw a second halo.
    @State private var isContextMenuVisible = false
    @State private var renderedSnapshot: (key: GridCalendar.HabitSnapshotKey, habit: Habit, value: GridCalendar.Snapshot)?
    @State private var graphWidth: CGFloat = 0
    @State private var checkPulse = false
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100
    private var recentWeeks: Int { ContributionChart.bandMetrics(width: graphWidth).weeks }

    private var snapshotRequest: GridCalendar.HabitSnapshotKey {
        GridCalendar.HabitSnapshotKey(habit: habit, weeks: recentWeeks, today: today, calendar: calendar)
    }

    private var cardSnapshot: GridCalendar.Snapshot? {
        guard graphWidth > 0 else { return nil }
        guard let renderedSnapshot else {
            return GridCalendar.cachedSnapshot(habit: habit, weeks: recentWeeks,
                                               today: today, calendar: calendar)
        }
        guard renderedSnapshot.key.canDisplaySnapshot(for: snapshotRequest) else { return nil }
        return Self.currentDaySnapshot(renderedSnapshot.value, previous: renderedSnapshot.habit,
                                       habit: habit, calendar: calendar)
    }

    private func loadCardSnapshot(for request: GridCalendar.HabitSnapshotKey) async {
        guard graphWidth > 0 else { return }
        let habit = habit
        if let cached = GridCalendar.cachedSnapshot(habit: habit, weeks: request.weeks,
                                                    today: request.today, calendar: request.calendar) {
            renderedSnapshot = (request, habit, cached)
            return
        }
        let signpost = StartupMetrics.begin("habitCardCalculation")
        defer { StartupMetrics.end("habitCardCalculation", id: signpost) }
        guard let snapshot = await ContributionSnapshotScheduler.perform({
            GridCalendar.snapshot(habit: habit, weeks: request.weeks,
                                  today: request.today, calendar: request.calendar)
        }), !Task.isCancelled, request == snapshotRequest else { return }
        renderedSnapshot = (request, habit, snapshot)
    }

    /// Refresh only today's tile while the shared queue calculates history.
    static func currentDaySnapshot(_ snapshot: GridCalendar.Snapshot, previous: Habit,
                                   habit: Habit, calendar: Calendar) -> GridCalendar.Snapshot {
        guard previous.id == habit.id, let column = snapshot.keys.indices.last,
              let row = snapshot.keys[column].firstIndex(of: snapshot.today) else { return snapshot }
        let intensity = GoalEngine.intensity(habit: habit, key: snapshot.today, calendar: calendar)
        let before = GoalEngine.dayCounts(habit: previous, day: snapshot.today, calendar: calendar)
        let after = GoalEngine.dayCounts(habit: habit, day: snapshot.today, calendar: calendar)
        guard snapshot.levels[column][row] != intensity || before != after else { return snapshot }
        var levels = snapshot.levels
        levels[column][row] = intensity
        return GridCalendar.Snapshot(weeks: snapshot.weeks, today: snapshot.today,
                                     keys: snapshot.keys, levels: levels, marks: snapshot.marks,
                                     filledCount: snapshot.filledCount + (after ? 1 : 0) - (before ? 1 : 0),
                                     streak: snapshot.streak)
    }

    private var today: String { DayKey.key(for: now, calendar: calendar) }
    private var habitStyle: PaletteStyle { palettes.style(for: habit) }

    /// Compact mode never shrinks action targets.
    private var headerHeight: CGFloat { Theme.Metrics.hit }

    /// Abstand Kopf -> eigenes Raster. Klein und absichtlich: der Kopf
    /// gehört zur Fläche DARUNTER.
    private var innerGap: CGFloat { collapsed ? designStyle.rowGap : designStyle.rowGap * 2 }

    /// Abstand zur nächsten Karte — immer ein Vielfaches des inneren
    /// Abstands, sonst liest sich der freistehende Kopf als Fußzeile der
    /// vorigen Karte statt als Überschrift der eigenen.
    private var outerGap: CGFloat { collapsed ? max(4, designStyle.cardOuterGap - 4) : designStyle.cardOuterGap }

    var body: some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("card.body")
        #endif
        return VStack(alignment: .leading, spacing: innerGap) {
            header
            meta
            revealingGrid
            if onDetails == nil { footer }
        }
        // Der Zug für das Aufziehen deckt die GANZE Zeile (Kopf + Karte):
        // vom Kopf aus gehen beide Seiten, über dem Raster entscheidet
        // `SwipeReveal.canBegin` (Historie vor Aufziehen, außer am Ende).
        .background {
            SwipeRevealPan(shouldBegin: revealShouldBegin,
                           began: { reveal.begin() },
                           changed: revealChanged,
                           ended: revealEnded,
                           cancelled: { snapReveal(to: 0) },
                           isOpen: { reveal.offset != 0 },
                           ownerID: habit.id)
        }
        // Der Zeilenabstand steckt bewusst HIER und nicht in `listRowInsets`:
        // Insets springen beim Umschalten, ein Padding wird animiert.
        .padding(.top, 4)
        .padding(.bottom, outerGap)
        // `.contain` ist hier Pflicht, nicht Deko: ein Identifier auf einem
        // Container ohne diese Angabe faltet den Teilbaum zu EINEM Element
        // zusammen — "check-today" und "habit-name" verschwinden dann aus
        // dem Baum und sind in XCUITest nicht mehr adressierbar. Als
        // Container bleibt die Karte selbst auffindbar UND ihre Knöpfe.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habit-card")
        .allowsHitTesting(!reveal.actionLock)
        .task(id: snapshotRequest) {
            await loadCardSnapshot(for: snapshotRequest)
        }
        .onChange(of: habit.log[today]) { oldValue, newValue in
            guard !reduceMotion, (newValue ?? 0) > (oldValue ?? 0),
                  !habit.isDeclined(today) else { return }
            checkPulse = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.02)) {
                checkPulse = false
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { checkPulse = false }
        }
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
        reveal.perform(action, reduceMotion: reduceMotion)
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
        reveal.snap(to: target, velocity: velocity, reduceMotion: reduceMotion)
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
    /// A tap opens history; the band fits the row and leaves horizontal drags to swipes.
    private var grid: some View {
            Group {
                if let snapshot = cardSnapshot {
                    recentGraph(snapshot: snapshot, viewportWidth: graphWidth)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onBackfill() }
                } else {
                    let weeks = recentWeeks
                    recentGraph(snapshot: GridCalendar.Snapshot(
                        weeks: weeks, today: today,
                        keys: Array(repeating: Array(repeating: nil, count: GridCalendar.rows), count: weeks),
                        levels: Array(repeating: Array(repeating: 0, count: GridCalendar.rows), count: weeks),
                        marks: [], filledCount: 0), viewportWidth: graphWidth)
                        .accessibilityLabel(String(localized: "Beitragskalender wird geladen"))
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                guard width > 0, abs(width - graphWidth) > 0.5 else { return }
                graphWidth = width
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isContextMenuVisible ? 0 : 1)
            // Die Trefferfläche ist die KARTE, nicht nur das, was in ihr
            // gezeichnet ist: ein langer Druck auf eine leere Ecke des
            // Rasters soll dasselbe tun wie einer auf eine Zelle.
            .contentShape(RoundedRectangle(cornerRadius: designStyle.cardRadius,
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
                GraphContextMenu(cardRadius: designStyle.cardRadius,
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
            }
            .onTapGesture {
                onBackfill()
            }
            .accessibilityAction(named: String(localized: "Historie"), onBackfill)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("habit-history")
    }

    /// The same chart and tiles as other app graphs, with a bounded recent window.
    func recentGraph(snapshot: GridCalendar.Snapshot, viewportWidth: CGFloat,
                     preview: Bool = false) -> some View {
        let gap = preview ? Self.previewGraphGap : GridCell.gap
        let width = viewportWidth.isFinite && viewportWidth > 0 ? viewportWidth : 12
        let cell = max(1, (width - CGFloat(max(0, snapshot.weeks - 1)) * gap)
                       / CGFloat(max(1, snapshot.weeks)))
        let chart = ContributionChart(snapshot: snapshot, cell: cell, gap: gap,
                                      width: width, showsMonthLabels: !preview && showsMonthLabels,
                                      labelScale: labelScale / 100,
                                      palette: Theme.adaptivePalette(habitStyle,
                                          preferences: appearancePreferences, dark: scheme == .dark),
                                      highlightsToday: true, checkPulse: !preview && checkPulse,
                                      showsSurface: !preview)
        return chart
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(habit.name): \(snapshot.filledCount) Tage in den letzten \(snapshot.weeks) Wochen."))
        .accessibilityIdentifier("contribution-grid")
    }

    // MARK: – Langer Druck: Vorschau + Aktionen
    //
    // The preview and row share recentGraph, ContributionChart and its tiles.
    // Each requests the columns fitting its own measured width. Older entries remain in history.

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

    /// Shared window sizing retained for reminder and statistics previews.
    /// Their callers may use the returned capacity; the habit row measures its own band.
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
    private var previewBandWidth: CGFloat {
        previewWidth - 2 * min(designStyle.cardPadding + 2, Theme.Metrics.gutter)
    }
    private var gridWeeks: Int { ContributionChart.bandMetrics(width: previewBandWidth, gap: Self.previewGraphGap).weeks }
    private static let previewGraphGap: CGFloat = 2

    private var habitPreview: some View {
        let snapshot = GridCalendar.snapshot(habit: habit,
                                             weeks: gridWeeks,
                                             today: today,
                                             calendar: calendar)
        let streak = snapshot.streak

        return VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: designStyle.rowGap))
                : AnyLayout(HStackLayout(spacing: designStyle.rowGap * 2))
            layout {
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
                        .font(designStyle.sectionTitleFont)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "Historie"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                previewMetric(value: snapshot.filledCount,
                              label: String(localized: "Tage"))
                if streak > 0 {
                    previewMetric(value: streak,
                                  label: String(localized: "Serie"),
                                  symbol: "flame.fill")
                }
            }
            recentGraph(snapshot: snapshot, viewportWidth: previewBandWidth, preview: true)
        }
        .padding(.horizontal, min(designStyle.cardPadding + 2, Theme.Metrics.gutter))
        .padding(.vertical, designStyle.cardPadding + 2)
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
                VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
                    HStack(alignment: .top, spacing: designStyle.rowGap * 2) {
                        nameRun
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: designStyle.rowGap * 2) {
                        Spacer(minLength: 0)
                        todayButton
                    }
                }
            } else {
                HStack(spacing: designStyle.rowGap * 2) {
                    nameRun
                    Spacer(minLength: designStyle.rowGap * 2)
                    todayButton
                }
                .frame(minHeight: headerHeight)
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

    /// Legacy callers keep their history route until they supply details.
    private var nameRun: some View {
        Button(action: onDetails ?? onBackfill) {
            nameContent
                .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("habit-name")
        .accessibilityLabel(habit.name)
        .accessibilityHint(onDetails == nil
            ? String(localized: "Öffnet die Historie dieses Habits.")
            : String(localized: "Öffnet die Details dieses Eintrags."))
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Label(String(localized: "Bearbeiten"), systemImage: "pencil")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Bearbeiten"))
        .accessibilityIdentifier("edit-habit")
    }

    private var footer: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: designStyle.rowGap))
            : AnyLayout(HStackLayout(spacing: designStyle.rowGap * 2))
        return layout {
            Button(action: onBackfill) {
                Label(String(localized: "Historie"), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open-habit-history")
            if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Metrics.gap) }
            editButton
        }
    }

    private var nameContent: some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !habit.emoji.isEmpty {
                    Text(habit.emoji).font(collapsed ? .subheadline : .title3)
                }
                Text(habit.name)
                    .font(collapsed ? designStyle.rowTitleFont : designStyle.sectionTitleFont)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : (collapsed ? 1 : 2))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if onDetails != nil {
                Label(String(localized: "Details"), systemImage: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// The same schedule sentence as the editor, using the item's calendar.
    private var meta: some View {
        Text(verbatim: RecurrenceText.summary(habit.recurrence,
                                             timeMinutes: habit.timeMinutes, calendar: calendar))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Visible in both modes: toggle, increment, or choose Yes/No.
    private var todayButton: some View {
        HabitActionControls(habit: habit, calendar: calendar, now: now,
                            onToggleDay: onToggleDay, onIncrement: onIncrement, onAnswer: onAnswer)
    }

}

/// Isolates the reveal offset from the habit header. The pan still lives on
/// the full row; only this layer reads `offset` on each drag frame.
private struct HabitSlidingGrid<Grid: View>: View {
    @Environment(\.appearancePreferences) private var appearancePreferences
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
                            .contentShape(RoundedRectangle(cornerRadius: appearancePreferences.designStyle.cardRadius,
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
