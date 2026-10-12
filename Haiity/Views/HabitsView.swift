import SwiftUI

/// Collection composition. The root retains filters, sorting and every mutation.
struct HabitsView<Row: View>: View {
    let habits: [Habit]
    let github: GitHubContributionSnapshot?
    let collapsed: Bool
    let showsUsername: Bool
    let showsMonthLabels: Bool
    @Binding var filter: HabitListFilter
    let onCreate: () -> Void
    @ViewBuilder let row: (Habit) -> Row
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        List {
            RootPageTitle(title: String(localized: "Habits"), compact: true)
                .id("habit-list-title")
                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
            if let github {
                GitHubContributionCard(snapshot: github, collapsed: collapsed,
                    showsUsername: showsUsername, showsMonthLabels: showsMonthLabels,
                    openProfile: { GitHubLink.open(github.profileURL) })
                    .equatable()
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Metrics.gutter, bottom: 0, trailing: Theme.Metrics.gutter))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            Picker(String(localized: "Typ"), selection: $filter.itemType) {
                Text(String(localized: "Alle")).tag(HabitListFilter.ItemType.all)
                Text(String(localized: "Habits")).tag(HabitListFilter.ItemType.habit)
                Text(String(localized: "Erinnerungen")).tag(HabitListFilter.ItemType.reminder)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: Theme.Metrics.hit)
            .accessibilityIdentifier("collection-type-filter")
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: Theme.Metrics.gutter, bottom: 8, trailing: Theme.Metrics.gutter))
            if habits.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: filter.isEmpty ? "Noch keine Habits" : "Keine passenden Einträge"), systemImage: "square.grid.3x3")
                } actions: {
                    if filter.isEmpty {
                        Button(String(localized: "Ersten Habit anlegen"), action: onCreate)
                            .accessibilityIdentifier("add-first-habit")
                    } else {
                        Button(String(localized: "Filter zurücksetzen")) { filter = HabitListFilter() }
                            .accessibilityIdentifier("reset-collection-filter")
                    }
                }
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(habits) { habit in
                row(habit).id(habit.id.uuidString).deleteDisabled(true)
            }
        }
        .accessibilityIdentifier("habit-list")
    }
}
