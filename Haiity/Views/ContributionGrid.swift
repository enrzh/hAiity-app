import SwiftUI

/// Das Herzstück: 53 Wochen × 7 Tage, Sonntag oben, scrollt zu heute.
/// Tippen auf eine vergangene Zelle trägt nach — Tage vergisst man mal.
struct ContributionGrid: View {
    let habit: Habit
    var weeks: Int = 53
    var cellSize: CGFloat = 11
    var gap: CGFloat = 3
    var interactive: Bool = true
    var onToggle: ((String) -> Void)?

    @Environment(\.colorScheme) private var scheme

    private var days: [[String?]] {
        // Spalten = Wochen, endend mit der aktuellen Woche; Zeilen So…Sa.
        let cal = Calendar.current
        let now = Date()
        let dow = cal.component(.weekday, from: now) - 1 // 0 = So
        guard let lastSat = cal.date(byAdding: .day, value: 6 - dow, to: now) else { return [] }
        var out: [[String?]] = []
        for w in 0..<weeks {
            var col: [String?] = []
            for r in 0..<7 {
                let offset = -(weeks * 7 - 1) + w * 7 + r
                guard let d = cal.date(byAdding: .day, value: offset, to: lastSat) else { col.append(nil); continue }
                col.append(d > now ? nil : DayKey.key(for: d))
            }
            out.append(col)
        }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(days.enumerated()), id: \.offset) { wi, col in
                        VStack(spacing: gap) {
                            ForEach(Array(col.enumerated()), id: \.offset) { _, key in
                                cell(key)
                            }
                        }
                        .id(wi)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { proxy.scrollTo(weeks - 1, anchor: .trailing) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gridSummary)
    }

    @ViewBuilder
    private func cell(_ key: String?) -> some View {
        let today = DayKey.today()
        if let key {
            let level = habit.intensity(key)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.level(level, dark: scheme == .dark))
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if key == today {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(.primary, lineWidth: 1.2)
                    }
                }
                .onTapGesture {
                    guard interactive else { return }
                    Theme.Haptics.check()
                    onToggle?(key)
                }
        } else {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.level(0, dark: scheme == .dark))
                .opacity(0.35)
                .frame(width: cellSize, height: cellSize)
        }
    }

    private var gridSummary: String {
        let total = habit.log.count
        return String(localized: "\(habit.name): \(total) Tage im letzten Jahr, aktuelle Serie \(habit.streak()).")
    }
}
