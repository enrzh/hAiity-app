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
    /// Zählt die eingetroffenen Deep-Links (siehe ContentView). Ein Link ist
    /// eine Absage an das, was gerade offen ist: der Tab wechselt unter dem
    /// Kaufblatt, und ohne dieses Signal bliebe der Nutzer auf einer
    /// Kaufseite sitzen, die zu einem Bereich gehört, den er verlassen hat.
    var routeToken: Int = 0
    /// Das Kaufblatt: `nil` heisst geschlossen.
    @State private var paywall: PaywallContext?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { scheme == .dark }
    private var accent: Color { Theme.accentText(palettes.style) }

    /// Der eine Lesepunkt dieser Seite — und ein beobachtbarer (siehe
    /// `ProStatus`). Der Kauf muss NICHT hier passieren: er kann über die
    /// vierte Habit, über die Einstellungen, auf einem anderen Gerät oder
    /// als bestätigte Familien-Kaufanfrage kommen. Genau dann darf die
    /// Statistik nicht gesperrt stehen bleiben.
    private var unlocked: Bool { Pro.isUnlocked }

    var body: some View {
        Group {
            if store.activeHabits.isEmpty {
                emptyState
            } else {
                statsList
            }
        }
        .sheet(item: $paywall) { context in
            // Hier gibt es nichts fortzusetzen: die Seite selbst IST das
            // Ziel und entsperrt sich mit dem Kauf.
            PaywallView(context: context, store: store, onUnlocked: {})
                .themed(store)
        }
        .onChange(of: routeToken) { _, _ in paywall = nil }
    }

    /// Ohne Habits keine Nullen-Wand: das Raster-Motiv und EIN Satz.
    private var emptyState: some View {
        VStack(spacing: 12) {
            RampSwatch(style: palettes.style, dark: dark, size: 16)
            Text(String(localized: "Noch keine Habits"))
                .font(.title3.bold())
            Text(String(localized: "Leg einen an und fang an, Quadrate zu füllen — jeder Tag, an dem du dranbleibst, färbt eine Zelle."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Statistik"))
    }

    private var statsList: some View {
        let snapshot = StatsEngine.snapshot(habits: store.activeHabits)
        return List {
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
                // Der Schnitt liegt auf der SEKTION, nicht mitten in einer
                // Karte: eine halbe Zeile („Quoten ja, Balken nein") wäre
                // eine kaputte Zeile. Die Daten bleiben unangetastet — hier
                // wird nur nicht gezeichnet.
                if unlocked {
                    ForEach(store.activeHabits) { habit in
                        StatsRow(habit: habit)
                            .modifier(StatsCardChrome())
                    }
                } else {
                    perHabitLockCard
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

    /// Das vereinigte Raster als HELD — volle Kartenbreite, satte Zellen.
    /// EIN VoiceOver-Element mit einem Satz (die Mini-Zellen einzeln wären
    /// eine Zumutung).
    ///
    /// Der Heute-Ring stand hier daneben und ist bewusst raus: die
    /// HEUTE-Kachel direkt darunter zeigt exakt dieselbe Zahl — und der
    /// doppelte Ring hat dem Raster die halbe Breite gestohlen, das dann
    /// klein und verloren in der Ecke saß (vom Gerät gemeldet).
    private func heroCard(_ snapshot: StatsEngine.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.cardPadding) {
            HStack(alignment: .center) {
                Text(String(localized: "Jahres-Puls"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer(minLength: 8)
                if snapshot.streak > 0 {
                    streakChip(snapshot.streak)
                }
            }
            pulse(snapshot)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !unlocked { paywall = .stats } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Jahres-Puls"))
        .accessibilityValue(pulseValue(snapshot))
        .accessibilityIdentifier("stats-card-yearPulse")
        .accessibilityAddTraits(unlocked ? [] : .isButton)
        .accessibilityAction { if !unlocked { paywall = .stats } }
    }

    /// Frei ist die KARTE (Titel und Serien-Chip), Pro ist das Ablesen des
    /// Rasters. Bewusst das ECHTE Raster, nur unscharf: ein erfundener
    /// Platzhalter wäre eine Behauptung über Daten, die längst da sind.
    /// Gerechnet und gespeichert wird unverändert weiter.
    @ViewBuilder
    private func pulse(_ snapshot: StatsEngine.Snapshot) -> some View {
        if unlocked {
            mergedGrid(snapshot.mergedLevels)
        } else {
            mergedGrid(snapshot.mergedLevels)
                .blur(radius: 5)
                .clipped()
                .overlay { pulseLockChip }
                // Der Tipp gehört der ganzen Karte, nicht dem Raster —
                // sonst hätte die Karte zwei Trefferzonen mit demselben Ziel.
                .allowsHitTesting(false)
        }
    }

    private var pulseLockChip: some View {
        Label(String(localized: "Nur mit hAiity Pro"), systemImage: "lock")
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityHidden(true)
    }

    private func pulseValue(_ snapshot: StatsEngine.Snapshot) -> String {
        guard unlocked else {
            // Der Serien-Chip steht auch gesperrt scharf auf der Karte. Ihn
            // durch „Nur mit hAiity Pro" zu ERSETZEN hiesse, dieselbe Karte
            // sagt Sehenden und Hörenden Unterschiedliches — gesperrt ist
            // das Raster, nicht die Serie.
            let locked = String(localized: "Nur mit hAiity Pro")
            guard snapshot.streak > 0 else { return locked }
            return String(localized: "Serie: \(snapshot.streak) Tage") + ". " + locked
        }
        return String(localized: "Alle Habits zusammen: heute \(snapshot.todayDone) von \(snapshot.todayTotal) erledigt, Gesamt-Serie \(snapshot.streak) Tage.")
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent(palettes.style).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Je Habit im Detail"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Quoten über 30, 90 und 365 Tage, beste Serie, Gesamtzahl und zwölf Monats-Balken — für jeden Habit einzeln."))
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

    /// Gemeinsame Form: KAPITÄLCHEN-Titel oben, Inhalt darunter, ein fester
    /// Mindest-Kasten — vier Kacheln, EINE Silhouette. Jede Kachel ist für
    /// VoiceOver EIN Element mit einem Satz.
    private func tile(_ title: String, identifier: String, value: String,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            Spacer(minLength: Theme.Metrics.gap)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                         style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
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

    private func streakTile(_ snapshot: StatsEngine.Snapshot) -> some View {
        tile(String(localized: "Serie"),
             identifier: "stats-card-streakFlame",
             value: String(localized: "Gesamt-Serie \(snapshot.streak) Tage, beste Serie \(snapshot.bestStreak).")) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: snapshot.streak > 0 ? "flame.fill" : "flame")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(flameColor(snapshot.streak))
                    Text(verbatim: "\(snapshot.streak)")
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                }
                Text(String(localized: "Best: \(snapshot.bestStreak)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func todayTile(_ snapshot: StatsEngine.Snapshot) -> some View {
        let done = snapshot.todayDone, total = snapshot.todayTotal
        return tile(String(localized: "Heute"),
                    identifier: "stats-card-todayRing",
                    value: total == 0
                        ? String(localized: "Heute ist nichts fällig")
                        : String(localized: "\(done) von \(total) erledigt")) {
            HStack(spacing: Theme.Metrics.cardPadding) {
                segmentedRing(done: done, total: total, size: 46, line: 5)
                VStack(alignment: .leading, spacing: 2) {
                    if total == 0 {
                        Text(String(localized: "Heute ist nichts fällig"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(verbatim: "\(done)/\(total)")
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        if done == total {
                            Label(String(localized: "Alles erledigt"),
                                  systemImage: "checkmark.seal.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(accent)
                        } else {
                            Text(String(localized: "\(done) von \(total) erledigt"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                sparkline(snapshot.last7)
                    .frame(height: 30)
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
    }

    private func totalsTile(_ snapshot: StatsEngine.Snapshot) -> some View {
        tile(String(localized: "Gesamt"),
             identifier: "stats-card-totals",
             value: String(localized: "Check-ins gesamt") + ": \(StatsMath.totalCheckIns(store.habits))") {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(StatsMath.totalCheckIns(store.habits))")
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(String(localized: "Check-ins gesamt"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Aktive Habits") + " · " + "\(store.activeHabits.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
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
    /// Sieben Punkte, 0…1: Linie mit weicher Fläche darunter — die Fläche
    /// gibt der Linie Gewicht, ohne eine zweite Farbe einzuführen.
    private func sparkline(_ values: [Double]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = values.count > 1 ? w / CGFloat(values.count - 1) : w
            let points = values.enumerated().map { i, value in
                CGPoint(x: CGFloat(i) * step, y: h - CGFloat(value) * (h - 4) - 2)
            }
            let line = Path { path in
                for (i, point) in points.enumerated() {
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            ZStack {
                if let first = points.first, let last = points.last {
                    var area = line
                    let _ = area.addLine(to: CGPoint(x: last.x, y: h))
                    let _ = area.addLine(to: CGPoint(x: first.x, y: h))
                    let _ = area.closeSubpath()
                    area.fill(LinearGradient(colors: [Theme.accent(palettes.style).opacity(0.22),
                                                      Theme.accent(palettes.style).opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                }
                line.stroke(accent, style: StrokeStyle(lineWidth: 2,
                                                       lineCap: .round, lineJoin: .round))
            }
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
    @Environment(\.palettes) private var palettes

    /// Die Farbfamilie DIESES Habits — Balken und Chip sprechen dieselbe
    /// Sprache wie sein Raster nebenan.
    private var style: PaletteStyle { palettes.style(for: habit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !habit.emoji.isEmpty { Text(habit.emoji) }
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                rowStreakChip(GoalEngine.streak(habit: habit))
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
            MonthBars(counts: StatsMath.monthlyCounts(habit: habit, months: 12),
                      style: style)
        }
        .accessibilityIdentifier("stats-row")
    }

    private func rowStreakChip(_ streak: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.caption2.weight(.semibold))
            Text(verbatim: "\(streak)")
                .font(.caption.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(streak > 0
                         ? AnyShapeStyle(Theme.accentText(style))
                         : AnyShapeStyle(.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(streak > 0
                    ? AnyShapeStyle(Theme.accent(style).opacity(0.14))
                    : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule())
        .accessibilityLabel(String(localized: "Serie: \(streak) Tage"))
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
