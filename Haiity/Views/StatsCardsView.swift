import SwiftUI

/// Die Statistik-Karten ÜBER dem „Habits"-Titel. Sie scrollen MIT der Liste
/// (sie sind eine Listenzeile, kein Overlay) und tragen dieselbe
/// Design-Sprache wie die Habit-Karten: weiße/#1C1C1E-Fläche,
/// `Theme.Metrics.cardRadius`, `cardPadding`.
///
/// **`Equatable`, und das ist Tempo, nicht Kosmetik** (dasselbe Muster wie
/// `HabitCard`): die Karten hängen sichtbar nur am vorgerechneten
/// `StatsEngine.Snapshot` und an der Kartenauswahl. Chrom-Umbauten (Tafel,
/// Toast, Zusammenziehen) reißen sie damit nicht mit. Gerechnet wird hier
/// NICHTS — der Schnappschuss kommt fertig und memoisiert herein.
///
/// Sind zwei Karten aktiv, stehen sie GESTAPELT: nebeneinander bricht auf
/// SE-Breite (320 pt) jede Karte mit Raster oder Satz — und zwei
/// verschieden dichte Karten in einer Reihe lesen sich wie eine Tabelle
/// ohne Kopf. Null aktive Karten heißt: dieser View wird gar nicht erst
/// eingehängt (kein leerer Behälter).
struct StatsCardsView: View, Equatable {
    static func == (a: StatsCardsView, b: StatsCardsView) -> Bool {
        a.snapshot == b.snapshot && a.cards == b.cards
    }

    let snapshot: StatsEngine.Snapshot
    let cards: [StatsCard]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Vorderseite/Rückseite der Puls-Karte. Lebt HIER, nicht im
    /// ContentView — ein Umblättern darf nur diese Karte neu bauen.
    @State private var pulseFlipped = false

    private var dark: Bool { scheme == .dark }
    private var accent: Color { Theme.accentText(palettes.style) }

    var body: some View {
        VStack(spacing: Theme.Metrics.gap) {
            ForEach(cards) { card in
                content(card)
                    .padding(Theme.Metrics.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                     style: .continuous))
            }
        }
        .accessibilityIdentifier("stats-cards")
    }

    @ViewBuilder
    private func content(_ card: StatsCard) -> some View {
        switch card {
        case .yearPulse:    yearPulse
        case .streakFlame:  streakFlame
        case .todayRing:    todayRing
        case .weekMomentum: weekMomentum
        }
    }

    // MARK: – Jahres-Puls

    /// Vereinigtes Mini-Raster aller Habits + Heute-Ring; ein Tipp blättert
    /// zur Serien-Liste je Habit um. EIN VoiceOver-Element mit einem Satz —
    /// 140 fokussierbare Mini-Zellen wären eine Zumutung.
    private var yearPulse: some View {
        HStack(spacing: Theme.Metrics.cardPadding) {
            if pulseFlipped {
                pulseBack
            } else {
                pulseFront
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if reduceMotion {
                pulseFlipped.toggle()
            } else {
                withAnimation(.snappy(duration: 0.24)) { pulseFlipped.toggle() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Jahres-Puls"))
        .accessibilityValue(pulseFlipped
            ? pulseBackSummary
            : String(localized: "Alle Habits zusammen: heute \(snapshot.todayDone) von \(snapshot.todayTotal) erledigt, Gesamt-Serie \(snapshot.streak) Tage."))
        .accessibilityHint(String(localized: "Zeigt beim Tippen die Serien je Habit."))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("stats-card-yearPulse")
    }

    private var pulseFront: some View {
        HStack(spacing: Theme.Metrics.cardPadding) {
            mergedMiniGrid
            Spacer(minLength: 0)
            ring(done: snapshot.todayDone, total: snapshot.todayTotal, size: 48, line: 5)
        }
    }

    /// Rückseite: Serie und Best je Habit, klein.
    private var pulseBack: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Serien je Habit"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if snapshot.perHabit.isEmpty {
                Text(String(localized: "Noch keine Habits"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(snapshot.perHabit.prefix(4).enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 6) {
                    Text(verbatim: "\(entry.emoji) \(entry.name)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(String(localized: "\(entry.current) · Best \(entry.best)"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pulseBackSummary: String {
        snapshot.perHabit.prefix(4)
            .map { String(localized: "\($0.name): Serie \($0.current), Best \($0.best)") }
            .joined(separator: ", ")
    }

    /// Das vereinigte Raster: dieselbe Rampe, kleinere Zellen, ~20 Wochen.
    private var mergedMiniGrid: some View {
        let cell: CGFloat = 7, gap: CGFloat = 2
        return HStack(alignment: .top, spacing: gap) {
            ForEach(Array(snapshot.mergedLevels.enumerated()), id: \.offset) { _, column in
                VStack(spacing: gap) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Theme.level(level, dark: dark, palette: palettes.style))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        // Chronologie läuft immer links -> rechts, wie im großen Raster.
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: – Streak-Flamme

    private var streakFlame: some View {
        HStack(spacing: Theme.Metrics.cardPadding) {
            Image(systemName: snapshot.streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: flameSize, weight: .semibold))
                .foregroundStyle(flameColor)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(snapshot.streak)")
                    .font(.system(size: 32, weight: .bold, design: .rounded)
                        .monospacedDigit())
                Text(String(localized: "Tage Gesamt-Serie"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(localized: "Best: \(snapshot.bestStreak)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(weekLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Streak-Flamme"))
        .accessibilityValue(String(localized: "Gesamt-Serie \(snapshot.streak) Tage, beste Serie \(snapshot.bestStreak). \(weekLine)."))
        .accessibilityIdentifier("stats-card-streakFlame")
    }

    /// Die Flamme wächst und färbt sich mit der Serie — gedeckelt, damit
    /// eine 300er-Serie die Karte nicht sprengt.
    private var flameSize: CGFloat {
        22 + min(14, CGFloat(snapshot.streak) * 0.5)
    }

    private var flameColor: Color {
        switch snapshot.streak {
        case ..<1:   return .secondary
        case ..<7:   return .orange
        case ..<30:  return Color(red: 1.0, green: 0.42, blue: 0.21)
        default:     return .red
        }
    }

    private var weekLine: String {
        guard snapshot.week.total > 0 else {
            return String(localized: "Woche: nichts fällig")
        }
        let pct = Int((snapshot.week.fraction * 100).rounded())
        return String(localized: "Woche: \(pct) %")
    }

    // MARK: – Heute-Ring

    private var todayRing: some View {
        let done = snapshot.todayDone, total = snapshot.todayTotal
        let complete = total > 0 && done == total
        return HStack(spacing: Theme.Metrics.cardPadding) {
            segmentedRing(done: done, total: total, size: 56, line: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Heute"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if total == 0 {
                    Text(String(localized: "Heute ist nichts fällig"))
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(String(localized: "\(done) von \(total) erledigt"))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                if complete {
                    // Dezent gefeiert: Farbe und Siegel statt Konfetti. Bei
                    // „Bewegung reduzieren" erscheint die Zeile ohne
                    // Skalierung — nur der Zustand, keine Bewegung.
                    Label(String(localized: "Alles erledigt"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .transition(reduceMotion
                                    ? AnyTransition.opacity
                                    : AnyTransition.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Heute-Ring"))
        .accessibilityValue(total == 0
            ? String(localized: "Heute ist nichts fällig")
            : String(localized: "\(done) von \(total) erledigt"))
        .accessibilityIdentifier("stats-card-todayRing")
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
    private func ring(done: Int, total: Int, size: CGFloat, line: CGFloat) -> some View {
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

    // MARK: – Wochen-Momentum

    private var weekMomentum: some View {
        HStack(spacing: Theme.Metrics.cardPadding) {
            sparkline
                .frame(width: 72, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: trendSymbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(trendColor)
                    Text(momentumSentence)
                        .font(.footnote.weight(.medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(String(localized: "Serie: \(snapshot.streak)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Wochen-Momentum"))
        .accessibilityValue(String(localized: "\(momentumSentence). Gesamt-Serie \(snapshot.streak) Tage."))
        .accessibilityIdentifier("stats-card-weekMomentum")
    }

    private var delta: Int? {
        StatsEngine.momentumDeltaPoints(current: snapshot.week,
                                        previous: snapshot.previousWeek)
    }

    /// Der Satz aus lokalisierbaren Stücken — „besser", „schlechter" oder
    /// neutral; ohne Vergleichswoche der schlichte Wochenstand.
    private var momentumSentence: String {
        guard let delta else {
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

    private var trendSymbol: String {
        guard let delta else { return "arrow.right" }
        if delta > 0 { return "arrow.up.right" }
        if delta < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var trendColor: Color {
        guard let delta else { return .secondary }
        if delta > 0 { return accent }
        if delta < 0 { return .orange }
        return .secondary
    }

    /// Sieben Punkte, 0…1, als eine Linie. Reines Zeichnen — die Werte
    /// stehen fertig im Schnappschuss.
    private var sparkline: some View {
        GeometryReader { geo in
            let values = snapshot.last7
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
