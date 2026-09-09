import SwiftUI

/// Statistik als EIGENER Bereich (Tab) — nicht mehr Karten über der
/// Habit-Liste plus Unterseite in „Mehr", sondern eine Seite, die beides
/// vereint:
///
///  1. **Jahres-Puls** als Held: das vereinigte Raster aller Habits über
///     die volle Kartenbreite, in der Sprache der App (dieselbe Rampe wie
///     die großen Raster; reine Nein-Tage in der Verneinungsfarbe).
///  2. **Vier Kacheln** im 2er-Raster: Serie, Heute, Woche, Gesamt — kurze
///     Zahlen, monospaced, eine Aussage je Kachel.
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

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
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
                RootPageTitle(title: String(localized: "Statistik"),
                              subtitle: String(localized: "Dein Rhythmus in einem Blick"))
                    .padding(.horizontal, -Theme.Metrics.gutter)
                Spacer(minLength: 72)
                RampSwatch(style: palettes.style, dark: dark, size: 16)
                Text(String(localized: "Noch keine Habits"))
                    .font(.title3.bold())
                Text(String(localized: "Lege deinen ersten Eintrag an."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer(minLength: 160)
            }
            .frame(maxWidth: .infinity, minHeight: 520)
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .coordinateSpace(.named(RootPageTitle.coordinateSpace))
        .onPreferenceChange(RootPageTitleProgressKey.self) { progress in
            if let progress { rootTitleProgress = progress }
        }
        .overlay(alignment: .top) {
            RootPageHeaderBlur(progress: rootTitleProgress)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statsList: some View {
        let snapshot = StatsEngine.snapshot(habits: visibleActiveTrackedHabits)
        let activeCards = viewPreferences.statsCards.active
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RootPageTitle(title: String(localized: "Statistik"),
                              subtitle: String(localized: "Dein Rhythmus in einem Blick"))
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

                if unlocked {
                    statsHabitRanking
                } else {
                    perHabitLockCard
                        .padding(Theme.Metrics.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface()
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .navigationBarTitleDisplayMode(.inline)
        .coordinateSpace(.named(RootPageTitle.coordinateSpace))
        .onPreferenceChange(RootPageTitleProgressKey.self) { progress in
            if let progress { rootTitleProgress = progress }
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

    private func statsTodayCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        let total = snapshot.todayTotal
        let done = snapshot.todayDone
        let open = max(total - done, 0)
        let weekPercent = Int((snapshot.week.fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: Theme.Metrics.cardPadding + 4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Heute"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if total == 0 {
                        Text(String(localized: "Kein Habit fällig"))
                            .font(.title2.weight(.bold))
                    } else {
                        Text("\(done)/\(total)")
                            .font(.system(.largeTitle, design: .default, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    Text(statsTodaySentence(snapshot))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                segmentedRing(done: done, total: total, size: 72, line: 8)
            }

            Divider()
                .opacity(0.55)

            HStack(spacing: 0) {
                statsTodayMetric(value: "\(open)", title: String(localized: "Offen"))
                statsTodayMetric(value: "\(snapshot.streak)", title: String(localized: "Aktuelle Serie"))
                statsTodayMetric(value: "\(weekPercent)%", title: String(localized: "Diese Woche"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Heute"))
        .accessibilityValue(total == 0
                            ? String(localized: "Kein Habit fällig")
                            : String(localized: "\(done) von \(total) erledigt"))
        .accessibilityIdentifier("stats-today-summary")
    }

    private func statsTodayMetric(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsTodaySentence(_ snapshot: StatsEngine.Snapshot) -> String {
        guard snapshot.todayTotal > 0 else {
            return String(localized: "Dein Tag ist frei.")
        }
        if snapshot.todayDone == snapshot.todayTotal {
            return String(localized: "Alles erledigt. Gute Arbeit.")
        }
        return String(localized: "Noch \(snapshot.todayTotal - snapshot.todayDone) offen")
    }

    private func statsRhythmCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        statsRhythmContent(snapshot)
            .padding(Theme.Metrics.cardPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface()
            .opacity(activeContextMenuID == StatsCard.yearPulse.rawValue ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if !unlocked { paywall = .stats }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Rhythmus"))
            .accessibilityValue(unlocked
                                ? String(localized: "Die letzten fünf Monate")
                                : String(localized: "Nur mit hAiity Pro"))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Rhythmus"))
                        .font(.headline.weight(.semibold))
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
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.top, 2)
        }
    }

    private func statsMetricGrid(_ snapshot: StatsEngine.Snapshot,
                                 cards: [StatsCard]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1),
                            GridItem(.flexible(), spacing: 1)],
                  spacing: 0) {
            ForEach(cards) { card in
                statsMetric(card, snapshot: snapshot)
                    .opacity(activeContextMenuID == card.rawValue ? 0 : 1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: statsMetricSymbol(card))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statsMetricColor(card, snapshot: snapshot))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer(minLength: 0)
            }
            Text(statsMetricValue(card, snapshot: snapshot))
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .lineLimit(1)
            Text(statsMetricTitle(card))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        case .totals: return "\(StatsMath.totalCheckIns(visibleActiveTrackedHabits))"
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

    private func statsMetricColor(_ card: StatsCard,
                                  snapshot: StatsEngine.Snapshot) -> Color {
        switch card {
        case .streakFlame: return flameColor(snapshot.streak)
        case .weekMomentum: return trendColor(snapshot)
        default: return accent
        }
    }

    private func statsWeekCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        let days = (-6...0).compactMap { offset in
            DayKey.shifted(snapshot.today, by: offset)
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Letzte 7 Tage"))
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                Text(momentumSentence(snapshot))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(trendColor(snapshot))
                    .lineLimit(1)
            }
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    let completion = StatsEngine.dailyCompletion(habits: visibleActiveTrackedHabits,
                                                                  day: day)
                    VStack(spacing: 7) {
                        Text(completion.total == 0
                             ? "-"
                             : "\(Int((completion.fraction * 100).rounded()))%")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(completion.total == 0 ? .tertiary : .primary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(completion.total == 0
                                  ? Color.primary.opacity(0.08)
                                  : accent.opacity(0.2 + completion.fraction * 0.8))
                            .frame(height: 30)
                        Text(statsWeekdayLabel(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.Metrics.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface()
        .accessibilityIdentifier("stats-week-card")
    }

    private func statsWeekdayLabel(_ key: String) -> String {
        guard let date = DayKey.date(from: key) else { return "-" }
        return date.formatted(.dateTime.weekday(.narrow))
    }

    private var statsHabitRanking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Deine Habits"))
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(Array(visibleActiveTrackedHabits.enumerated()), id: \.element.id) { index, habit in
                    statsHabitRow(habit)
                        .opacity(activeContextMenuID == "habit-\(habit.id.uuidString)" ? 0 : 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(habit.name)
                        .accessibilityValue(statsHabitAccessibilityValue(habit))
                        .accessibilityIdentifier("stats-row")
                        .overlay {
                            statsContextMenu(id: "habit-\(habit.id.uuidString)", preview: {
                                statsPreview(statsHabitRow(habit),
                                             height: statsRowPreviewHeight)
                            }, height: statsRowPreviewHeight)
                            .accessibilityHidden(true)
                        }
                    if index < visibleActiveTrackedHabits.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
            .padding(.vertical, 4)
            .appSurface()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stats-habit-ranking")
        }
    }

    private func statsHabitRow(_ habit: Habit) -> some View {
        let completion = Int((GoalEngine.completion(habit: habit, lastNDays: 30) * 100).rounded())
        let streak = GoalEngine.streak(habit: habit)
        let style = palettes.style(for: habit)
        return HStack(spacing: 10) {
            Text(habit.emoji.isEmpty ? "-" : habit.emoji)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(Theme.accent(style).opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(String(localized: "30 Tage: \(completion)%"))
                    Text("·")
                    Text(String(localized: "Serie \(streak)"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                MonthBars(counts: StatsMath.monthlyCounts(habit: habit, months: 12),
                          style: style)
                    .frame(height: 22)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func statsHabitAccessibilityValue(_ habit: Habit) -> String {
        let completion = Int((GoalEngine.completion(habit: habit, lastNDays: 30) * 100).rounded())
        let streak = GoalEngine.streak(habit: habit)
        return String(localized: "30 Tage: \(completion) Prozent, Serie \(streak) Tage")
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
            HStack(alignment: .top, spacing: Theme.Metrics.gap) {
                Image(systemName: "lock")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent(palettes.style).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Je Habit im Detail"))
                        .font(.subheadline.weight(.semibold))
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
        let cell = pitch - gap
        return HStack(alignment: .top, spacing: gap) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, column in
                VStack(spacing: gap) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
                            .fill(Theme.level(level, dark: dark, palette: palettes.style))
                            .frame(width: cell, height: cell)
                    }
                }
            }
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

    private func statsContextMenu(id: String,
                                  preview: @escaping () -> AnyView,
                                  height: CGFloat)
        -> some View {
        GraphContextMenu(cardRadius: Theme.Metrics.cardRadius,
                         previewWidth: statsPreviewWidth,
                         previewHeight: height,
                         // The preview builder owns the one rounded surface;
                         // the bridge must not wrap it a second time.
                         previewOwnsSurface: true,
                         previewAccessibilityIdentifier: "stats-preview",
                         preview: preview,
                         actions: statsContextActions,
                         commit: openStatsAdjustments,
                         onMenuVisibilityChanged: { visible in
                             if visible {
                                 activeContextMenuID = id
                             } else if activeContextMenuID == id {
                                 activeContextMenuID = nil
                             }
                         })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statsPreview<Content: View>(_ content: Content,
                                             height: CGFloat) -> AnyView {
        let surfaced = AnyView(content
                .padding(16)
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

    private func flameColor(_ streak: Int) -> Color {
        switch streak {
        case ..<1:   return .secondary
        case ..<7:   return .orange
        case ..<30:  return Color(red: 1.0, green: 0.42, blue: 0.21)
        default:     return .red
        }
    }

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

    /// Der Satz aus lokalisierbaren Stücken — „besser", „schlechter" oder
    /// neutral; ohne Vergleichswoche der schlichte Wochenstand.
    private func momentumSentence(_ snapshot: StatsEngine.Snapshot) -> String {
        guard let delta = momentumDelta(snapshot) else {
            guard snapshot.week.total > 0 else {
                return String(localized: "Diese Woche ist nichts fällig")
            }
            let pct = Int((snapshot.week.fraction * 100).rounded())
            return String(localized: "Diese Woche: \(pct) % erledigt")
        }
        if delta > 0 { return String(localized: "\(delta) % besser als letzte Woche") }
        if delta < 0 { return String(localized: "\(-delta) % schlechter als letzte Woche") }
        return String(localized: "Genau wie letzte Woche")
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
