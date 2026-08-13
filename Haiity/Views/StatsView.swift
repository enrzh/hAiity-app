import SwiftUI

/// Statistik als EIGENER Bereich (Tab) — nicht mehr Karten über der
/// Habit-Liste plus Unterseite in „Mehr", sondern eine Seite, die beides
/// vereint:
///
///  1. **Jahres-Puls** als Held: das vereinigte Raster aller Habits in der
///     Sprache der App (dieselbe Rampe wie die großen Raster), daneben der
///     Heute-Ring.
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

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { scheme == .dark }
    private var accent: Color { Theme.accentText(palettes.style) }

    var body: some View {
        let snapshot = StatsEngine.snapshot(habits: store.activeHabits)
        List {
            Section {
                heroCard(snapshot)
                    .modifier(StatsCardChrome())
                tileGrid(snapshot)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0,
                                              leading: Theme.Metrics.gutter,
                                              bottom: Theme.Metrics.gap,
                                              trailing: Theme.Metrics.gutter))
            }
            Section {
                ForEach(store.activeHabits) { habit in
                    StatsRow(habit: habit)
                        .modifier(StatsCardChrome())
                }
            } header: {
                if !store.activeHabits.isEmpty {
                    Text(String(localized: "Je Habit"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.leading, Theme.Metrics.gutter)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Statistik"))
    }

    // MARK: – Held: Jahres-Puls

    /// Vereinigtes Raster + Heute-Ring. EIN VoiceOver-Element mit einem Satz
    /// — die Mini-Zellen einzeln wären eine Zumutung.
    private func heroCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Jahres-Puls"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if snapshot.streak > 0 {
                    (Text(Image(systemName: "flame.fill")) +
                     Text(verbatim: " \(snapshot.streak)"))
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            HStack(spacing: Theme.Metrics.cardPadding) {
                mergedGrid(snapshot.mergedLevels)
                Spacer(minLength: 0)
                progressRing(done: snapshot.todayDone,
                             total: snapshot.todayTotal,
                             size: 56, line: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Jahres-Puls"))
        .accessibilityValue(String(localized: "Alle Habits zusammen: heute \(snapshot.todayDone) von \(snapshot.todayTotal) erledigt, Gesamt-Serie \(snapshot.streak) Tage."))
        .accessibilityIdentifier("stats-card-yearPulse")
    }

    /// Das vereinigte Raster: dieselbe Rampe wie überall, kleine Zellen.
    private func mergedGrid(_ levels: [[Int]]) -> some View {
        let cell: CGFloat = 8, gap: CGFloat = 2
        return HStack(alignment: .top, spacing: gap) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, column in
                VStack(spacing: gap) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                            .fill(Theme.level(level, dark: dark, palette: palettes.style))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        // Chronologie läuft immer links -> rechts, wie im großen Raster.
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: – Kacheln

    private func tileGrid(_ snapshot: StatsEngine.Snapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Metrics.gap),
                            GridItem(.flexible(), spacing: Theme.Metrics.gap)],
                  spacing: Theme.Metrics.gap) {
            streakTile(snapshot)
            todayTile(snapshot)
            weekTile(snapshot)
            totalsTile(snapshot)
        }
    }

    /// Gemeinsame Form: Titelzeile klein und sekundär, darunter die eine
    /// große Zahl bzw. Grafik — jede Kachel EIN Element für VoiceOver.
    private func tile(_ title: String, identifier: String, value: String,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                         style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private func streakTile(_ snapshot: StatsEngine.Snapshot) -> some View {
        tile(String(localized: "Serie"),
             identifier: "stats-card-streakFlame",
             value: String(localized: "Gesamt-Serie \(snapshot.streak) Tage, beste Serie \(snapshot.bestStreak).")) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Image(systemName: snapshot.streak > 0 ? "flame.fill" : "flame")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(flameColor(snapshot.streak))
                Text(verbatim: "\(snapshot.streak)")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                Spacer(minLength: 0)
            }
            Text(String(localized: "Best: \(snapshot.bestStreak)"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func todayTile(_ snapshot: StatsEngine.Snapshot) -> some View {
        let done = snapshot.todayDone, total = snapshot.todayTotal
        return tile(String(localized: "Heute"),
                    identifier: "stats-card-todayRing",
                    value: total == 0
                        ? String(localized: "Heute ist nichts fällig")
                        : String(localized: "\(done) von \(total) erledigt")) {
            HStack(spacing: Theme.Metrics.gap) {
                segmentedRing(done: done, total: total, size: 44, line: 5)
                VStack(alignment: .leading, spacing: 2) {
                    if total == 0 {
                        Text(String(localized: "Heute ist nichts fällig"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(verbatim: "\(done)/\(total)")
                            .font(.title3.weight(.bold).monospacedDigit())
                        if done == total {
                            Label(String(localized: "Alles erledigt"),
                                  systemImage: "checkmark.seal.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
        }
    }

    private func weekTile(_ snapshot: StatsEngine.Snapshot) -> some View {
        tile(String(localized: "Woche"),
             identifier: "stats-card-weekMomentum",
             value: momentumSentence(snapshot)) {
            sparkline(snapshot.last7)
                .frame(height: 26)
            HStack(spacing: 4) {
                Image(systemName: trendSymbol(snapshot))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(trendColor(snapshot))
                Text(momentumSentence(snapshot))
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func totalsTile(_ snapshot: StatsEngine.Snapshot) -> some View {
        tile(String(localized: "Gesamt"),
             identifier: "stats-card-totals",
             value: String(localized: "Check-ins gesamt") + ": \(StatsMath.totalCheckIns(store.habits))") {
            Text(verbatim: "\(StatsMath.totalCheckIns(store.habits))")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
            Text(String(localized: "Check-ins gesamt"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "Aktive Habits") + ": " + "\(store.activeHabits.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
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

    /// Einfacher Fortschritts-Ring (Jahres-Puls rechts): EIN Bogen, Anteil
    /// erledigt, Zahl in der Mitte.
    private func progressRing(done: Int, total: Int, size: CGFloat, line: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color(.quaternaryLabel), lineWidth: line)
            if total > 0 {
                Circle()
                    .trim(from: 0, to: Double(done) / Double(total))
                    .stroke(accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(verbatim: "\(done)/\(total)")
                .font(.caption2.weight(.bold).monospacedDigit())
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

    private func trendSymbol(_ snapshot: StatsEngine.Snapshot) -> String {
        guard let delta = momentumDelta(snapshot) else { return "arrow.right" }
        if delta > 0 { return "arrow.up.right" }
        if delta < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private func trendColor(_ snapshot: StatsEngine.Snapshot) -> Color {
        guard let delta = momentumDelta(snapshot) else { return .secondary }
        if delta > 0 { return accent }
        if delta < 0 { return .orange }
        return .secondary
    }

    /// Sieben Punkte, 0…1, als eine Linie. Reines Zeichnen — die Werte
    /// stehen fertig im Schnappschuss.
    private func sparkline(_ values: [Double]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = values.count > 1 ? w / CGFloat(values.count - 1) : w
            Path { path in
                for (i, value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * step,
                                        y: h - CGFloat(value) * (h - 4) - 2)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(accent, style: StrokeStyle(lineWidth: 2,
                                               lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Kartenchrom für die Statistik-Liste: dieselbe Fläche, derselbe Radius wie
/// die Habit-Karten — die Seite spricht die Sprache der Liste nebenan.
private struct StatsCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                             style: .continuous))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                      leading: Theme.Metrics.gutter,
                                      bottom: Theme.Metrics.gap,
                                      trailing: Theme.Metrics.gutter))
    }
}

private struct StatsRow: View {
    let habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !habit.emoji.isEmpty { Text(habit.emoji) }
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("🔥 \(GoalEngine.streak(habit: habit))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                completionCell(days: 30)
                completionCell(days: 90)
                completionCell(days: 365)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(localized: "Best: \(GoalEngine.bestStreak(habit: habit))"))
                    // Bei Ja/Nein sagt „Gesamt" nur die halbe Wahrheit: es
                    // zählt die Ja-Tage. Die Zahl daneben ist die, die es
                    // bei keiner anderen Art gibt — und die einzige, die
                    // beantwortet, ob ein Habit gerade läuft oder nur
                    // ungefragt bleibt.
                    Text(String(localized: "Gesamt: \(habit.checkInCount())"))
                    if habit.kind == .yesNo {
                        Text(String(localized: "Nein: \(habit.declinedCount())"))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            MonthBars(counts: StatsMath.monthlyCounts(habit: habit, months: 12))
        }
        .accessibilityIdentifier("stats-row")
    }

    private func completionCell(days: Int) -> some View {
        let pct = Int((GoalEngine.completion(habit: habit, lastNDays: days) * 100).rounded())
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(pct) %")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(String(localized: "\(days) Tage"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 12 dünne Kapseln, eine pro Monat (älteste links), Höhe relativ zum
/// stärksten Monat — bewusst ohne Beschriftung, ein Mini-Sparkline.
private struct MonthBars: View {
    let counts: [Int]
    @Environment(\.palettes) private var palettes

    var body: some View {
        let peak = max(counts.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                Capsule()
                    .fill(count > 0 ? Theme.accent(palettes.style) : Color(.tertiarySystemFill))
                    .frame(width: 5, height: max(4, 34 * CGFloat(count) / CGFloat(peak)))
            }
        }
        .frame(height: 36, alignment: .bottom)
        // Chronologie nie spiegeln — wie beim Contribution-Grid.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Check-ins der letzten 12 Monate: \(counts.reduce(0, +))"))
    }
}
