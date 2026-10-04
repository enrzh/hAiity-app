import SwiftUI

/// Statistik als EIGENER Bereich (Tab) — nicht mehr Karten über der
/// Habit-Liste plus Unterseite in „Mehr", sondern eine Seite, die beides
/// vereint:
///
///  1. **Rhythmus** als Held: das vereinigte Raster aller Habits über
///     die volle Kartenbreite, in der Sprache der App (dieselbe Rampe wie
///     die großen Raster; reine Nein-Tage in der Verneinungsfarbe).
///  2. **Check-ins** als einzige Standard-Kachel. Serie, Heute und Woche
///     bleiben in der Anpassung; sie stehen schon auf der Heute- und
///     Wochenkarte.
///  3. **Je Habit** die vertraute Zeile: Quoten 30/90/365, Serien, Summe und
///     12 Monats-Balken.
///
/// Die Mathematik liegt komplett in StatsEngine/StatsMath/GoalEngine
/// (unit-getestet); hier wird nur gezeichnet. Der Schnappschuss ist
/// memoisiert — eine `body`-Auswertung kostet den Gleichheitsvergleich.
struct StatsView: View {
    let store: HabitStore
    let viewPreferences: ViewPreferencesStore
    /// Zählt die eingetroffenen Deep-Links (siehe ContentView). Ein Link ist
    /// eine Absage an das, was gerade offen ist: der Tab wechselt unter dem
    /// Kaufblatt, und ohne dieses Signal bliebe der Nutzer auf einer
    /// Kaufseite sitzen, die zu einem Bereich gehört, den er verlassen hat.
    var routeToken: Int = 0
    /// Das Kaufblatt: `nil` heisst geschlossen.
    @State private var paywall: PaywallContext?
    @State private var showingCardSettings = false
    @State private var proStatus = ProStatus.shared
    @State private var activeContextMenuID: String?
    @State private var rootTitleProgress: CGFloat = 0
    /// A cold statistics calculation must never block the tab transition.
    /// The last completed value remains visible while changed data is
    /// recalculated in the background.
    @State private var renderedSnapshot: StatsEngine.Snapshot?
    /// What the reading block is doing. It is always rendered — the block is the
    /// affordance, so it cannot disappear when there is nothing to show yet.
    @State private var statsReadingPhase: StatsReadingPhase = .idle
    @State private var renderedRefreshKey: String?
    @State private var statsReadingTask: Task<Void, Never>?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }
    private var dark: Bool { scheme == .dark }
    private var accent: Color { Theme.accentText(palettes.style) }

    /// Der eine Lesepunkt dieser Seite — und ein beobachtbarer (siehe
    /// `ProStatus`). Der Kauf muss NICHT hier passieren: er kann über die
    /// vierte Habit, über die Einstellungen oder auf einem anderen Gerät
    /// kommen. Genau dann darf die Statistik nicht gesperrt stehen bleiben.
    private var unlocked: Bool {
        _ = proStatus.unlocked
        return Pro.isUnlocked
    }

    private var visibleActiveHabits: [Habit] {
        ProGate.visibleActiveHabits(store.activeHabits, unlocked: unlocked)
    }

    private var visibleActiveTrackedHabits: [Habit] {
        visibleActiveHabits.filter(\.isTrackedHabit)
    }

    private var statsRefreshKey: String {
        "\(store.data.updatedAt)|\(unlocked)|\(DayKey.today())|\(Calendar.current.firstWeekday)|\(Calendar.current.timeZone.identifier)|\(Locale.current.identifier)"
    }

    private func loadStatsSnapshot() async {
        let refreshKey = statsRefreshKey
        let habits = visibleActiveTrackedHabits
        let today = DayKey.today()
        let calendar = Calendar.current
        let statsSignpost = StartupMetrics.begin("statsCalculation")
        defer { StartupMetrics.end("statsCalculation", id: statsSignpost) }
        guard let snapshot = await ContributionSnapshotScheduler.perform({
            StatsEngine.snapshot(habits: habits, today: today, calendar: calendar)
        }), !Task.isCancelled, refreshKey == statsRefreshKey else { return }
        renderedSnapshot = snapshot
        renderedRefreshKey = refreshKey
        restoreStatsReadingIfAny()
    }

    var body: some View {
        Group {
            if visibleActiveTrackedHabits.isEmpty {
                emptyState
            } else {
                statsList
            }
        }
        .sheet(item: $paywall) { context in
            // Hier gibt es nichts fortzusetzen: die Seite selbst IST das
            // Ziel und entsperrt sich mit dem Kauf.
            PaywallView(context: context, store: store, onUnlocked: {})
                .themed(store, palettes: palettes)
        }
        .sheet(isPresented: $showingCardSettings) {
            statsAdjustmentSheet
        }
        .onChange(of: routeToken) { _, _ in paywall = nil }
        .onChange(of: statsRefreshKey) { _, _ in cancelStatsReading() }
        .onDisappear { cancelStatsReading() }
        .task(id: statsRefreshKey) {
            await loadStatsSnapshot()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                RootPageCompactTitle(title: String(localized: "Statistik"),
                                     progress: rootTitleProgress)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(action: openStatsAdjustments) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(String(localized: "Statistik anpassen"))
                .accessibilityIdentifier("stats-adjustments")
            }
        }
        .navigationChrome()
    }

    /// Ohne Habits keine Nullen-Wand: derselbe Titelrahmen wie auf der vollen
    /// Seite, danach das Raster-Motiv und EIN Satz.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                statsPageTitle
                    .padding(.horizontal, -Theme.Metrics.gutter)
                Spacer(minLength: 72)
                RampSwatch(style: palettes.style, dark: dark, size: 16)
                Text(String(localized: "Noch keine Habits"))
                    .font(designStyle.sectionTitleFont)
                Text(String(localized: "Lege deinen ersten Eintrag an und hake ihn ab, damit dein Raster sichtbar wächst."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    openURL(AppDestination.create.url)
                } label: {
                    Text(String(localized: "Ersten Habit anlegen"))
                        .font(designStyle.rowTitleFont)
                        .padding(.horizontal, designStyle.cardPadding + 4)
                        .padding(.vertical, 8)
                        .background(Theme.accentFill(palettes.style), in: Capsule())
                        .foregroundStyle(.white)
                }
                .frame(minHeight: Theme.Metrics.hit)
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-first-habit")
                Spacer(minLength: 160)
            }
            .frame(maxWidth: .infinity, minHeight: 520)
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.floatingControlsClearance)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .coordinateSpace(.named(RootPageTitle.coordinateSpace))
        .onPreferenceChange(RootPageTitleProgressKey.self) { progress in
            guard let progress else { return }
            let collapsed = progress >= 0.5 ? 1 : 0
            if rootTitleProgress != CGFloat(collapsed) {
                rootTitleProgress = CGFloat(collapsed)
            }
        }
        .overlay(alignment: .top) {
            RootPageHeaderBlur(progress: rootTitleProgress)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var statsList: some View {
        if let snapshot = renderedSnapshot {
            statsListContent(snapshot)
        } else {
            statsLoadingState
        }
    }

    private func statsListContent(_ snapshot: StatsEngine.Snapshot) -> some View {
        let activeCards = viewPreferences.statsCards.active
        return ScrollView {
            VStack(alignment: .leading, spacing: designStyle.sectionGap) {
                statsPageTitle
                    .padding(.horizontal, -Theme.Metrics.gutter)

                statsTodayCard(snapshot)

                if activeCards.contains(.yearPulse) {
                    statsRhythmCard(snapshot)
                }

                let metricCards = activeCards.filter { $0 != .yearPulse }
                if !metricCards.isEmpty {
                    statsMetricGrid(snapshot, cards: metricCards)
                }

                statsWeekCard(snapshot)

                statsReadingCard

                if unlocked {
                    statsHabitRanking(snapshot)
                } else {
                    perHabitLockCard
                        .padding(designStyle.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface()
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.floatingControlsClearance)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .navigationBarTitleDisplayMode(.inline)
        .coordinateSpace(.named(RootPageTitle.coordinateSpace))
        .onPreferenceChange(RootPageTitleProgressKey.self) { progress in
            guard let progress else { return }
            let collapsed = progress >= 0.5 ? 1 : 0
            if rootTitleProgress != CGFloat(collapsed) {
                rootTitleProgress = CGFloat(collapsed)
            }
        }
        .overlay(alignment: .top) {
            RootPageHeaderBlur(progress: rootTitleProgress)
        }
        .overlay {
            if activeContextMenuID?.hasPrefix("habit-") == true {
                // iOS renders UIContextMenu previews in a system-owned layer
                // that is not always part of the app accessibility snapshot.
                // Keep a non-interactive boundary in our tree so assistive
                // technology and UI tests can still address the lifted card.
                Rectangle()
                    .fill(.clear)
                    .frame(width: statsPreviewWidth,
                           height: statsRowPreviewHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Statistikvorschau"))
                    .accessibilityIdentifier("stats-preview")
                    .allowsHitTesting(false)
            }
        }
    }

    private var statsLoadingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: designStyle.sectionGap) {
                statsPageTitle
                    .padding(.horizontal, -Theme.Metrics.gutter)

                statsTodayLoadingCard
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.floatingControlsClearance)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .navigationBarTitleDisplayMode(.inline)
        .coordinateSpace(.named(RootPageTitle.coordinateSpace))
        .onPreferenceChange(RootPageTitleProgressKey.self) { progress in
            guard let progress else { return }
            let collapsed = progress >= 0.5 ? 1 : 0
            if rootTitleProgress != CGFloat(collapsed) {
                rootTitleProgress = CGFloat(collapsed)
            }
        }
        .overlay(alignment: .top) {
            RootPageHeaderBlur(progress: rootTitleProgress)
        }
    }

    /// No subtitle: the page's first card already says what today is, and a
    /// "your rhythm at a glance" line only restates the title.
    private var statsPageTitle: some View {
        RootPageTitle(title: String(localized: "Statistik"))
    }

    private var statsTodayLoadingCard: some View {
        statsTodayCard(statsLoadingSnapshot)
            .redacted(reason: .placeholder)
            .accessibilityElement(children: .ignore)
            .allowsHitTesting(false)
            .accessibilityLabel(String(localized: "Statistik wird geladen"))
            .accessibilityIdentifier("stats-loading-today")
    }

    private var statsLoadingSnapshot: StatsEngine.Snapshot {
        StatsEngine.Snapshot(today: DayKey.today(), todayDone: 0, todayTotal: 0,
                             streak: 0, bestStreak: 0,
                             week: .init(done: 0, total: 0),
                             previousWeek: .init(done: 0, total: 0),
                             last7: [], last7HasData: [], mergedLevels: [],
                             perHabit: [], totalCheckIns: 0)
    }

    private func statsTodayCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        let total = snapshot.todayTotal
        let done = snapshot.todayDone
        return VStack(alignment: .leading, spacing: designStyle.cardPadding + 6) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: designStyle.rowGap * 2))
                : AnyLayout(HStackLayout(spacing: designStyle.cardPadding + 4))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Heute"))
                        .font(designStyle.rowTitleFont)
                        .foregroundStyle(.secondary)
                    if total == 0 {
                        Text(String(localized: "Kein Habit fällig"))
                            .font(designStyle.sectionTitleFont)
                    } else {
                        Text("\(done)/\(total)")
                            .font((designStyle == .studio ? Font.largeTitle.weight(.bold)
                                   : designStyle.pageTitleFont).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    Text(statsTodaySentence(snapshot))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                segmentedRing(done: done, total: total, size: 72, line: 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Heute"))
            .accessibilityValue(statsTodayAccessibilityValue(snapshot))
            .accessibilityIdentifier("stats-today-summary")
            DisclosureGroup {
                Text(statsDailyExplanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stats-today-explanation")
            } label: {
                Text(String(localized: "Details"))
                    .frame(minHeight: Theme.Metrics.hit, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .font(.caption)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stats-today-details")
        }
        .padding(designStyle.cardPadding + 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface()
        .accessibilityElement(children: .contain)
    }

    private var statsDailyExplanation: String {
        String(localized: "Hier zählen heute geplante Habits; flexible Ziele nach Tagesplan, nicht nach erfüllter Periode. Mengen zählen ab dem Zielwert, Ja/Nein nur mit Ja.")
    }

    /// One sentence carries what the removed three-column footer repeated.
    /// The same numbers stay in `statsTodayAccessibilityValue`.
    /// One sentence about the pattern over time, written on device — but only
    /// when the reader asks for it.
    ///
    /// **Why a tap instead of a page load.** Running the model makes the device
    /// warm, and this page is the one people open most often. Generating on
    /// every visit would spend heat continuously, which is exactly the cost the
    /// person should get to decide about. So the block is always visible and
    /// the work starts only on a tap.
    ///
    /// **Why it is always visible.** An affordance that appears only once it has
    /// a result is invisible until it is useful, which is how a feature like
    /// this stays undiscovered. The block is the invitation; its content
    /// changes. That also means the "unavailable" state has to be a real,
    /// explained state rather than a missing card.
    @ViewBuilder
    private var statsReadingCard: some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            HStack(spacing: designStyle.rowGap * 2) {
                AppIconBadge(symbol: "text.quote")
                Text(String(localized: "Dein Muster"))
                    .font(designStyle.rowTitleFont)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            switch statsReadingPhase {
            case .idle:
                statsReadingIdleBody
            case .working:
                HStack(spacing: designStyle.rowGap * 2) {
                    ProgressView()
                    Text(String(localized: "Denkt nach…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .shown(let text):
                statsReadingShownBody(text)
            case .unavailable(let reason):
                Text(statsReadingUnavailableText(reason))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed:
                VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
                    Text(String(localized: "Das hat nicht geklappt."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    statsReadingButton(title: String(localized: "Erneut versuchen")) {
                        requestStatsReading(reroll: true)
                    }
                }
            }
        }
        .padding(designStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if appearancePreferences.backgroundMode != .color || appearancePreferences.backgroundColorHex != nil {
                SettingsRowSurface()
                    .clipShape(RoundedRectangle(cornerRadius: designStyle.cardRadius))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stats-reading")
    }

    private var statsReadingIdleBody: some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            Text(statsReadingIdleText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            statsReadingButton(title: String(localized: "Kurz zusammenfassen")) {
                requestStatsReading(reroll: false)
            }
        }
    }

    @ViewBuilder
    private func statsReadingShownBody(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            // A re-roll is a second deliberate request for the same heat the
            // first one cost, so it is offered but never automatic.
            statsReadingButton(title: String(localized: "Anderer Satz")) {
                requestStatsReading(reroll: true)
            }
        }
    }

    private func statsReadingButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .frame(minHeight: Theme.Metrics.hit)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(statsReadingPhase == .working || renderedRefreshKey != statsRefreshKey)
        .accessibilityIdentifier("stats-reading-action")
    }

    /// The block has to say something useful before it asks for work. With no
    /// habits or no history there is no pattern to describe, and inviting a tap
    /// that would then decline is worse than saying so up front.
    private var statsReadingIdleText: String {
        guard let snapshot = renderedSnapshot else {
            return String(localized: "Aus deinen Zahlen wird ein Satz.")
        }
        return StatsReadingFacts(snapshot: snapshot).hasSomethingToSay
            ? String(localized: "Aus deinen Zahlen wird ein Satz.")
            : String(localized: "Sobald du Check-ins hast, steht hier ein Satz dazu.")
    }

    private func statsReadingUnavailableText(_ reason: OnDeviceModelAvailability) -> String {
        switch reason {
        case .available:
            return String(localized: "Aus deinen Zahlen wird ein Satz.")
        case .appleIntelligenceOff:
            return String(localized: "Apple Intelligence ist aus. Schalte sie in den iOS-Einstellungen ein.")
        case .modelNotReady:
            return String(localized: "Das Modell lädt noch.")
        case .deviceNotEligible:
            return String(localized: "Dieses Gerät kann das Modell nicht ausführen.")
        case .unsupportedSystem:
            return String(localized: "Das braucht iOS 26.")
        }
    }

    private func restoreStatsReadingIfAny() {
        guard let snapshot = renderedSnapshot else { return }
        let facts = StatsReadingFacts(snapshot: snapshot)
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        statsReadingPhase = StatsReadingDaily.cachedReading(
            for: DayKey.today(), facts: facts, language: language,
            in: SharedStorage.defaults).map(StatsReadingPhase.shown) ?? .idle
    }

    private func cancelStatsReading() {
        statsReadingTask?.cancel()
        statsReadingTask = nil
        statsReadingPhase = .idle
    }

    private func requestStatsReading(reroll: Bool) {
        guard statsReadingPhase != .working, renderedRefreshKey == statsRefreshKey else { return }
        statsReadingPhase = .working
        statsReadingTask = Task { await generateStatsReading(reroll: reroll) }
    }

    private func generateStatsReading(reroll: Bool) async {
        guard let snapshot = renderedSnapshot, renderedRefreshKey == statsRefreshKey else { return }
        let refreshKey = statsRefreshKey
        let reason = OnDeviceModel.availability
        guard reason == .available else {
            statsReadingPhase = .unavailable(reason)
            return
        }
        let facts = StatsReadingFacts(snapshot: snapshot)
        guard facts.hasSomethingToSay else {
            statsReadingPhase = .failed
            return
        }
        let dayKey = DayKey.today()
        let defaults = SharedStorage.defaults
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let text = await StatsReadingDaily.write(
            for: dayKey, facts: facts, language: language, defaults: defaults,
            reroll: reroll,
            isCurrent: { refreshKey == statsRefreshKey && renderedRefreshKey == refreshKey },
            write: StatsReadingDaily.onDeviceWriter)

        guard !Task.isCancelled, refreshKey == statsRefreshKey else { return }
        statsReadingPhase = text.map(StatsReadingPhase.shown) ?? .failed
    }

    private func statsTodaySentence(_ snapshot: StatsEngine.Snapshot) -> String {
        guard snapshot.todayTotal > 0 else {
            return String(localized: "Dein Tag ist frei.")
        }
        if snapshot.todayDone == snapshot.todayTotal {
            return String(localized: "Alles erledigt. Gute Arbeit.")
        }
        let weekPercent = Int((snapshot.week.fraction * 100).rounded())
        return String(localized: "Noch \(snapshot.todayTotal - snapshot.todayDone) offen · Serie \(snapshot.streak) · Woche \(weekPercent) %")
    }

    private func statsTodayAccessibilityValue(_ snapshot: StatsEngine.Snapshot) -> String {
        let open = max(snapshot.todayTotal - snapshot.todayDone, 0)
        let weekPercent = Int((snapshot.week.fraction * 100).rounded())
        let metrics = String(localized: "\(open) offen, Serie \(snapshot.streak), diese Woche \(weekPercent) Prozent")
        if snapshot.todayTotal == 0 {
            return String(localized: "Kein Habit fällig, \(metrics)")
        }
        return String(localized: "\(snapshot.todayDone) von \(snapshot.todayTotal) erledigt, \(metrics)")
    }

    private func statsRhythmCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        statsRhythmContent(snapshot)
            .padding(designStyle.cardPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface()
            .opacity(activeContextMenuID == StatsCard.yearPulse.rawValue ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if !unlocked { paywall = .stats }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Rhythmus"))
            .accessibilityValue(statsRhythmAccessibilityValue(snapshot))
            .accessibilityAddTraits(unlocked ? [] : .isButton)
            .accessibilityAction {
                if !unlocked { paywall = .stats }
            }
            .accessibilityIdentifier("stats-rhythm-card")
            .overlay {
                statsContextMenu(id: StatsCard.yearPulse.rawValue, preview: {
                    statsPreview(statsRhythmContent(snapshot),
                                 height: statsHeroPreviewHeight)
                }, height: statsHeroPreviewHeight)
            }
    }

    private func statsRhythmContent(_ snapshot: StatsEngine.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: designStyle.cardPadding) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Rhythmus"))
                        .font(designStyle.sectionTitleFont)
                    Text(String(localized: "Die letzten fünf Monate"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if snapshot.streak > 0 {
                    streakChip(snapshot.streak)
                }
            }
            ZStack {
                mergedGrid(snapshot.mergedLevels)
                    .blur(radius: unlocked ? 0 : 5)
                if !unlocked {
                    Label(String(localized: "Nur mit hAiity Pro"),
                          systemImage: "lock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        // A plain tonal fill, not a material. This is CONTENT —
                        // a badge inside a card — and the app's own rule is that
                        // content never carries glass: over a card that already has
                        // a surface, a material here samples a second layer and
                        // the badge turns into a grey smudge.
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
            .padding(.top, 2)
        }
    }

    private func statsRhythmAccessibilityValue(_ snapshot: StatsEngine.Snapshot) -> String {
        guard unlocked else { return String(localized: "Nur mit hAiity Pro") }
        let filled = snapshot.mergedLevels.reduce(0) { total, column in
            total + column.reduce(0) { count, level in count + (level > 0 ? 1 : 0) }
        }
        return String(localized: "\(filled) Tage in den letzten fünf Monaten")
    }

    private func statsMetricGrid(_ snapshot: StatsEngine.Snapshot,
                                 cards: [StatsCard]) -> some View {
        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                  ? [GridItem(.flexible())]
                  : [GridItem(.flexible(), spacing: 1),
                     GridItem(.flexible(), spacing: 1)],
                  spacing: 0) {
            ForEach(cards) { card in
                statsMetric(card, snapshot: snapshot)
                    .opacity(activeContextMenuID == card.rawValue ? 0 : 1)
                    .padding(.horizontal, designStyle.cardPadding + 4)
                    .padding(.vertical, designStyle.cardPadding + 3)
                    .frame(maxWidth: .infinity, minHeight: designStyle.settingsRowHeight + 40, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(statsMetricTitle(card))
                    .accessibilityValue(statsMetricValue(card, snapshot: snapshot))
                    .accessibilityIdentifier("stats-card-\(card.rawValue)")
                    .overlay {
                        statsContextMenu(id: card.rawValue, preview: {
                            statsPreview(statsMetric(card, snapshot: snapshot),
                                         height: statsTilePreviewHeight)
                        }, height: statsTilePreviewHeight)
                    }
            }
        }
        .appSurface()
        .accessibilityIdentifier("stats-metrics")
    }

    @ViewBuilder
    private func statsMetric(_ card: StatsCard,
                             snapshot: StatsEngine.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap + 3) {
            HStack {
                Image(systemName: statsMetricSymbol(card))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statsMetricColor(card, snapshot: snapshot))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
                    Spacer(minLength: 0)
            }
            Text(statsMetricValue(card, snapshot: snapshot))
                .font((designStyle == .studio ? Font.title3.weight(.semibold)
                       : designStyle.sectionTitleFont).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Text(statsMetricTitle(card))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statsMetricTitle(_ card: StatsCard) -> String {
        switch card {
        case .yearPulse: return String(localized: "Rhythmus")
        case .streakFlame: return String(localized: "Tage Serie")
        case .todayRing: return String(localized: "Heute")
        case .weekMomentum: return String(localized: "Diese Woche")
        case .totals: return String(localized: "Check-ins")
        }
    }

    private func statsMetricValue(_ card: StatsCard,
                                  snapshot: StatsEngine.Snapshot) -> String {
        switch card {
        case .yearPulse: return "-"
        case .streakFlame: return "\(snapshot.streak)"
        case .todayRing: return "\(snapshot.todayDone)/\(snapshot.todayTotal)"
        case .weekMomentum:
            return "\(Int((snapshot.week.fraction * 100).rounded()))%"
        case .totals: return "\(snapshot.totalCheckIns)"
        }
    }

    private func statsMetricSymbol(_ card: StatsCard) -> String {
        switch card {
        case .yearPulse: return "square.grid.3x3.middle.filled"
        case .streakFlame: return "flame.fill"
        case .todayRing: return "circle.dashed"
        case .weekMomentum: return "chart.line.uptrend.xyaxis"
        case .totals: return "number"
        }
    }

    /// The accent means progress; the trend sentence keeps the only other
    /// status color. A heat ramp on the streak icon used to compete with the
    /// user's own palette, so the streak is a number now.
    private func statsMetricColor(_ card: StatsCard,
                                  snapshot: StatsEngine.Snapshot) -> Color {
        switch card {
        case .weekMomentum: return trendColor(snapshot)
        default: return accent
        }
    }

    private func statsWeekCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: designStyle.cardPadding) {
            statsWeekSummary(snapshot)
            DisclosureGroup {
                Text(statsWeekExplanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stats-week-explanation")
            } label: {
                Text(String(localized: "Details"))
                    .frame(minHeight: Theme.Metrics.hit, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .font(.caption)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stats-week-details")
        }
        .padding(designStyle.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface()
        .accessibilityElement(children: .contain)
    }

    private func statsWeekSummary(_ snapshot: StatsEngine.Snapshot) -> some View {
        let days = (-6...0).compactMap { offset in
            DayKey.shifted(snapshot.today, by: offset)
        }
        return VStack(alignment: .leading, spacing: designStyle.cardPadding) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Letzte 7 Tage"))
                    .font(designStyle.sectionTitleFont)
                Text(Self.momentumSentence(current: snapshot.week, previous: snapshot.previousWeek))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let fraction = snapshot.last7.indices.contains(index) ? snapshot.last7[index] : 0
                    let hasData = snapshot.last7HasData.indices.contains(index) && snapshot.last7HasData[index]
                    VStack(spacing: 7) {
                        Text(hasData ? "\(Int((fraction * 100).rounded()))%" : "-")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(hasData ? .primary : .tertiary)
                        // Same square, same ramp as every other graph in the app.
                        // No second chart language, no new component: GridCell already
                        // owns the tile geometry.
                        GridCell(color: hasData
                                 ? Theme.level(Self.statsDayLevel(fraction), dark: dark, palette: palettes.style)
                                 : Color(.quaternaryLabel),
                                size: GridCell.size * 2.5)
                        Text(statsWeekdayLabel(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Letzte 7 Tage"))
        .accessibilityValue(statsWeekAccessibilityValue(snapshot))
        .accessibilityIdentifier("stats-week-card")
    }

    private var statsWeekExplanation: String {
        String(localized: "Die Wochenquote zählt feste Termine bis heute und flexible Wochenziele; Vergleich: volle Vorwoche. Flexible Monats- und Jahresziele zählen nicht. – heißt: nichts fällig.")
    }

    private func statsWeekAccessibilityValue(_ snapshot: StatsEngine.Snapshot) -> String {
        let days = (-6...0).compactMap { DayKey.shifted(snapshot.today, by: $0) }
        let percents = days.enumerated().map { index, _ -> String in
            let fraction = snapshot.last7.indices.contains(index) ? snapshot.last7[index] : 0
            let hasData = snapshot.last7HasData.indices.contains(index) && snapshot.last7HasData[index]
            return hasData ? "\(Int((fraction * 100).rounded())) %" : "-"
        }.joined(separator: ", ")
        return "\(percents), \(Self.momentumSentence(current: snapshot.week, previous: snapshot.previousWeek))"
    }

    /// Maps a day fraction onto the same 0…4 ramp the contribution tiles use.
    /// ponytail: four quarter-buckets, not a continuous gradient. `floor` rather
    /// than `round`/`ceil` on purpose — with `ceil` a 67% and a 75% day both land
    /// on level 3 and a real difference disappears. With `floor`, 100% is the
    /// only level 4 and each quarter of the range is its own bucket. The exact
    /// percentage stays visible above the square and in the accessibility value.
    static func statsDayLevel(_ fraction: Double) -> Int {
        guard fraction > 0 else { return 0 }
        return min(4, max(1, Int(floor(fraction * 4))))
    }

    private func statsWeekdayLabel(_ key: String) -> String {
        guard let date = DayKey.date(from: key) else { return "-" }
        return date.formatted(.dateTime.weekday(.narrow))
    }

    private func statsHabitRanking(_ snapshot: StatsEngine.Snapshot) -> some View {
        let statsByID = Dictionary(uniqueKeysWithValues: snapshot.perHabit.map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: designStyle.rowGap * 2 + 2) {
            Text(String(localized: "Deine Habits"))
                .font(designStyle.sectionTitleFont)
                .padding(.horizontal, 2)
            DisclosureGroup {
                Text(String(localized: "30-Tage-Quote: erfüllte von geplanten Terminen; bei Ja/Nein zählen auch Antworten an freien Tagen. Flexible Ziele: erfüllte Perioden; die laufende zählt erst, wenn sie erfüllt ist."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stats-habit-explanation")
            } label: {
                Text(String(localized: "Details"))
                    .frame(minHeight: Theme.Metrics.hit, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .font(.caption)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stats-habit-details")
            LazyVStack(spacing: 0) {
                ForEach(Array(visibleActiveTrackedHabits.enumerated()), id: \.element.id) { index, habit in
                    if let habitStats = statsByID[habit.id] {
                        statsHabitRow(habit, stats: habitStats)
                        .opacity(activeContextMenuID == "habit-\(habit.id.uuidString)" ? 0 : 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(habit.name)
                        .accessibilityValue(statsHabitAccessibilityValue(habit, stats: habitStats))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { openHabit(habit.id) }
                        .accessibilityIdentifier("stats-row")
                        .overlay {
                            statsContextMenu(id: "habit-\(habit.id.uuidString)", preview: {
                                statsPreview(statsHabitRow(habit, stats: habitStats),
                                             height: statsRowPreviewHeight)
                            }, height: statsRowPreviewHeight)
                            .accessibilityHidden(true)
                        }
                    }
                    if index < visibleActiveTrackedHabits.count - 1 {
                        Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    }
                }
            }
            .padding(.horizontal, designStyle.cardPadding)
            .padding(.vertical, 4)
            .appSurface()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stats-habit-ranking")
        }
    }

    private func statsHabitRow(_ habit: Habit, stats: StatsEngine.HabitStreaks) -> some View {
        let completion = Int((stats.completion30 * 100).rounded())
        let streak = stats.current
        let style = palettes.style(for: habit)
        return HStack(spacing: designStyle.rowGap * 2 + 2) {
            Text(habit.emoji.isEmpty ? "-" : habit.emoji)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(Theme.accent(style).opacity(0.12), in: RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: designStyle.rowGap / 2 + 1) {
                Text(habit.name)
                    .font(designStyle.rowTitleFont)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(String(localized: "30 Tage: \(completion)%"))
                    Text("·")
                    Text(String(localized: "Serie \(streak)"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                MonthBars(counts: stats.monthlyCounts,
                          style: style)
                    .padding(.vertical, designStyle.graphPadding)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, designStyle.cardPadding - 2)
        .frame(minHeight: Theme.Metrics.hit)
        .accessibilityElement(children: .combine)
    }

    private func statsHabitAccessibilityValue(_ habit: Habit,
                                              stats: StatsEngine.HabitStreaks) -> String {
        let completion = Int((stats.completion30 * 100).rounded())
        let streak = stats.current
        return String(localized: "30 Tage: \(completion) Prozent, Serie \(streak) Tage")
    }

    private func openHabit(_ id: UUID) {
        openURL(AppDestination.habit(id).url)
    }

    private func openStatsAdjustments() {
        guard unlocked else {
            paywall = .stats
            return
        }
        showingCardSettings = true
    }

    private var statsAdjustmentSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StatsCard.allCases) { card in
                        Toggle(isOn: cardBinding(card)) {
                            Label(card.displayName, systemImage: card.symbol)
                        }
                        .accessibilityIdentifier("stats-adjustment-\(card.rawValue)")
                    }
                } header: {
                    Text(String(localized: "Statistikkarten"))
                }
                .settingsListRow()
            }
            .settingsSurface()
            .appPageHeader(String(localized: "Statistik anpassen"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Fertig")) {
                        showingCardSettings = false
                    }
                }
            }
        }
        .themed(store, palettes: palettes)
        .environment(\.appearanceBackgroundOwned, false)
        .presentationDetents([.medium, .large])
    }

    private func cardBinding(_ card: StatsCard) -> Binding<Bool> {
        Binding(
            get: { viewPreferences.statsCards.isActive(card) },
            set: { active in viewPreferences.setStatsCard(card, active: active) })
    }

    /// Statt der Zeilen EINE Karte in derselben Form — kein Banner, keine
    /// zweite Farbe, kein Ausrufezeichen. Sie NENNT, was fehlt, statt zu
    /// rufen, dass etwas fehlt.
    private var perHabitLockCard: some View {
        Button {
            paywall = .stats
        } label: {
            HStack(alignment: .top, spacing: designStyle.rowGap * 2) {
                Image(systemName: "lock")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent(palettes.style).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Je Habit im Detail"))
                        .font(designStyle.rowTitleFont)
                    Text(String(localized: "Details für jedes Habit."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "Mit hAiity Pro freischalten"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stats-pro-lock")
    }

    /// Gemessene Kartenbreite fürs Puls-Raster — feste SPALTENZAHL, die
    /// Zellgröße fällt aus der Breite (dasselbe Prinzip wie das große
    /// Raster: mehr Platz heißt größere Quadrate, nicht mehr Spalten).
    @State private var pulseWidth: CGFloat = 0

    private func mergedGrid(_ levels: [[Int]]) -> some View {
        let columns = max(levels.count, 1)
        let pitch = pulseWidth > 0 ? pulseWidth / CGFloat(columns) : 15
        let gap = min(3, max(2, pitch * 0.16))
        let cell = max(1, pitch - gap)
        let snapshot = GridCalendar.Snapshot(
            weeks: levels.count,
            today: "",
            keys: levels.map { column in column.map { _ in "" as String? } },
            levels: levels,
            marks: [],
            filledCount: 0)
        return ContributionTiles(
            snapshot: snapshot,
            cell: cell,
            gap: gap,
            radius: cell * 0.24,
            rows: levels.first?.count ?? GridCalendar.rows) { level in
                Theme.level(level, dark: dark, palette: palettes.style)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                pulseWidth = width
            }
            // Chronologie läuft immer links -> rechts, wie im großen Raster.
            .environment(\.layoutDirection, .leftToRight)
    }

    private var statsPreviewWidth: CGFloat {
        HabitCard.previewMetrics(windowWidth: HabitCard.windowWidth()).width
    }

    /// Each stats shape gets its own preview height. A single hero-sized
    /// height made the compact tiles look like blank sliding panels.
    private let statsHeroPreviewHeight: CGFloat = 180
    private let statsTilePreviewHeight: CGFloat = 104
    private let statsRowPreviewHeight: CGFloat = 116

    private var statsContextActions: [GraphMenuAction] {
        [GraphMenuAction(title: String(localized: "Statistik anpassen"),
                         symbol: "slider.horizontal.3",
                         handler: openStatsAdjustments)]
    }

    /// The habit behind a `"habit-<uuid>"` context-menu id, or nil for the
    /// page-level menu.
    ///
    /// These two live out here rather than as locals inside the menu function:
    /// a `@ViewBuilder` reads an `if/else` as a view branch, so deciding a
    /// closure inside one only works behind an explicit `return` — which turns
    /// the result builder off for the whole body and warns about it. Deciding
    /// before the view expression is both correct and quieter.
    private func statsContextHabitID(_ id: String) -> UUID? {
        guard id.hasPrefix("habit-") else { return nil }
        return UUID(uuidString: String(id.dropFirst("habit-".count)))
    }

    /// A per-habit card opens its habit; the page-level menu opens the settings.
    private func statsContextCommit(for id: String) -> () -> Void {
        guard let habitID = statsContextHabitID(id) else { return openStatsAdjustments }
        return { openHabit(habitID) }
    }

    @ViewBuilder
    private func statsContextMenu(id: String,
                                  preview: @escaping () -> AnyView,
                                  height: CGFloat)
        -> some View {
        GraphContextMenu(cardRadius: designStyle.cardRadius,
                         previewWidth: statsPreviewWidth,
                         previewHeight: height,
                         // The preview builder owns the one rounded surface;
                         // the bridge must not wrap it a second time.
                         previewOwnsSurface: true,
                         previewAccessibilityIdentifier: "stats-preview",
                         preview: preview,
                         actions: statsContextActions,
                         commit: statsContextCommit(for: id),
                         performsCommitOnTap: statsContextHabitID(id) != nil,
                         onMenuVisibilityChanged: { visible in
                             if visible {
                                 activeContextMenuID = id
                             } else if activeContextMenuID == id {
                                 activeContextMenuID = nil
                             }
                         })
            .frame(maxWidth: statsPreviewWidth)
    }

    private func statsPreview<Content: View>(_ content: Content,
                                             height: CGFloat) -> AnyView {
        let surfaced = AnyView(content
                .padding(designStyle.cardPadding + 4)
                .frame(width: statsPreviewWidth, alignment: .topLeading)
                .appSurface())

        // The preview owns one surface and only reserves the compact height
        // needed by UIKit. Its content remains free to grow for Dynamic Type.
        let framed = AnyView(surfaced
            .frame(width: statsPreviewWidth, alignment: .topLeading)
            .frame(minHeight: height, alignment: .topLeading)
            .environment(\.appearancePreferences, store.appearancePreferences)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Statistikvorschau"))
            .accessibilityIdentifier("stats-preview"))
        return framed
    }

    /// Die Serie als Kapsel-Chip — dieselbe Form im Held und je Habit, damit
    /// „Serie" überall gleich aussieht.
    private func streakChip(_ streak: Int, palette: PaletteStyle? = nil) -> some View {
        let style = palette ?? palettes.style
        let text = Theme.accentText(style)
        return HStack(spacing: 3) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.caption2.weight(.semibold))
            Text(verbatim: "\(streak)")
                .font(.caption.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(streak > 0 ? AnyShapeStyle(text) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(streak > 0
                    ? AnyShapeStyle(Theme.accent(style).opacity(0.14))
                    : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule())
        .accessibilityHidden(true)
    }

    // MARK: – kleine Zeichenhelfer

    /// Ring mit einem SEGMENT je heute fälligem Habit; erledigte Segmente in
    /// der Akzentfarbe. Bei 0 fälligen: ein leerer gestrichelter Ring.
    @ViewBuilder
    private func segmentedRing(done: Int, total: Int, size: CGFloat, line: CGFloat) -> some View {
        ZStack {
            if total == 0 {
                Circle()
                    .stroke(Color(.quaternaryLabel),
                            style: StrokeStyle(lineWidth: line, dash: [3, 4]))
            } else {
                let gap = min(0.03, 0.25 / Double(total))
                ForEach(0..<total, id: \.self) { i in
                    let start = Double(i) / Double(total)
                    let end = Double(i + 1) / Double(total) - gap
                    Circle()
                        .trim(from: start, to: max(start, end))
                        .stroke(i < done ? accent : Color(.quaternaryLabel),
                                style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .frame(width: size, height: size)
        .padding(line / 2)
    }

    private func momentumDelta(_ snapshot: StatsEngine.Snapshot) -> Int? {
        StatsEngine.momentumDeltaPoints(current: snapshot.week,
                                        previous: snapshot.previousWeek)
    }

    static func momentumSentence(current: StatsEngine.DayCompletion,
                                 previous: StatsEngine.DayCompletion,
                                 bundle: Bundle = .main,
                                 locale: Locale = .current) -> String {
        guard let delta = StatsEngine.momentumDeltaPoints(current: current, previous: previous) else {
            guard current.total > 0 else {
                return String(localized: "Diese Woche ist nichts fällig", bundle: bundle, locale: locale)
            }
            let pct = Int((current.fraction * 100).rounded())
            return String(localized: "Diese Woche: \(pct) % erledigt", bundle: bundle, locale: locale)
        }
        if delta > 0 { return String(localized: "\(delta) Prozentpunkte höher als letzte Woche", bundle: bundle, locale: locale) }
        if delta < 0 { return String(localized: "\(-delta) Prozentpunkte niedriger als letzte Woche", bundle: bundle, locale: locale) }
        return String(localized: "Gleiche Quote wie letzte Woche", bundle: bundle, locale: locale)
    }

    private func trendColor(_ snapshot: StatsEngine.Snapshot) -> Color {
        guard let delta = momentumDelta(snapshot) else { return .secondary }
        if delta > 0 { return accent }
        if delta < 0 { return .orange }
        return .secondary
    }

}

/// 12 dünne Kapseln, eine pro Monat (älteste links), Höhe relativ zum
/// stärksten Monat — bewusst ohne Beschriftung, ein Mini-Sparkline.
private struct MonthBars: View {
    let counts: [Int]
    let style: PaletteStyle

    var body: some View {
        let peak = max(counts.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 5) {
            // Leere Monate: ein leiser 3-pt-Punkt statt der 4-pt-Kapsel in
            // Tertiär — zwölf gleich hohe „Mini-Balken" lasen sich wie eine
            // kaputte Anzeige, nicht wie „nichts passiert".
            ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                Capsule()
                    .fill(count > 0 ? Theme.accent(style) : Color(.quaternarySystemFill))
                    .frame(width: 5, height: count > 0
                           ? max(6, 34 * CGFloat(count) / CGFloat(peak)) : 3)
            }
        }
        .frame(height: 36, alignment: .bottom)
        // Chronologie nie spiegeln — wie beim Contribution-Grid.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Check-ins der letzten 12 Monate: \(counts.reduce(0, +))"))
    }
}
