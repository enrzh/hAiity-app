import SwiftUI

extension MoreView {
    var habitBehaviorSettings: some View {
        // Not a `List`: iOS 27 drops taps on grouped list rows, and this page is
        // nothing but tappable settings controls.
        SettingsPage {
                cloudSyncSection
                autoArchiveSection
                swipeActionsSection
                notificationActionsSection
                defaultTimeZoneGroup
                calendarSection
                // In a group, like every other control on this page. A bare
                // moreHubRow has no panel around it, so the row sat straight on
                // the wallpaper while everything above and below it was in glass.
                AppSettingsGroup(title: String(localized: "Auf dem Gerät"),
                                 footer: String(localized: "Datums- und Zeitangaben funktionieren ohne Download. Zusätzliche Unterstützung ist optional und bleibt auf dem Gerät.")) {
                    // A push, not another sheet. This page is a second level of
                    // Verhalten & Teilen, and presenting a sheet over it meant a
                    // second set of chrome — its own grabber, its own close
                    // button, a dismiss that threw away the page underneath —
                    // for something that is simply the next screen. The stack
                    // already has a navigationDestination for MoreRoute, so this
                    // is what the developer row does.
                    NavigationLink(value: MoreRoute.localModel) {
                        AppSettingsRow(title: String(localized: "Text-Erstellung"),
                                       symbol: "text.badge.plus",
                                       showsChevron: true) {
                            EmptyView()
                        }
                    }
                    .accessibilityIdentifier("open-local-model")
                }
        }
    }

    private var cloudSyncSection: some View {
        AppSettingsGroup(title: String(localized: "Synchronisierung")) {
            AppSettingsRow(title: cloudStatus.state.title,
                           detail: cloudStatus.state.detail,
                           symbol: cloudStatus.state.systemImage) {
                EmptyView()
            }
            .accessibilityElement(children: .combine)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cloud-sync-status")
        }
    }

    /// One toggle, so it gets the same row treatment as every other setting:
    /// an icon, one short imperative title, and the consequence underneath. The
    /// old title spelled out the mechanism ("automatisch archivieren") that the
    /// caption and the toggle's own immediacy already convey.
    private var autoArchiveSection: some View {
        AppSettingsGroup(title: String(localized: "Archivierung")) {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                Toggle(isOn: Binding(
                    get: { statsCards.preferences.autoArchiveCompletedItems },
                    set: { enabled in
                        statsCards.update { $0.autoArchiveCompletedItems = enabled }
                    })) {
                    AppSettingsRow(title: String(localized: "Einmalige archivieren"),
                                   symbol: "archivebox") {
                        EmptyView()
                    }
                }
                .accessibilityIdentifier("auto-archive-completed-items-toggle")

                Text(String(localized: "Erledigte einmalige Einträge und letzte Wiederholungen landen automatisch im Archiv."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Align with the row title, not the card edge: this is the
                    // caption for the row above, and `AppSettingsRow` already
                    // lines its own detail up with its title. Derived from the
                    // badge so it survives a metric change.
                    .padding(.leading, Theme.Metrics.glyph + Theme.Metrics.gap + 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    /// The default time zone is an app-wide default, so it belongs with the
    /// app-wide behavior controls rather than as a loose row on the hub. The
    /// selector itself is unchanged: a full-row native `Menu`.
    private var defaultTimeZoneGroup: some View {
        AppSettingsGroup(title: String(localized: "Standardzeitzone")) {
            defaultTimeZonePicker
        }
    }

    private var defaultTimeZonePicker: some View {
        Menu {
            Button {
                store.defaultTimeZoneIdentifier = nil
            } label: {
                if store.defaultTimeZoneIdentifier == nil {
                    Label(String(localized: "Gerätezeitzone"), systemImage: "checkmark")
                } else {
                    Text(String(localized: "Gerätezeitzone"))
                }
            }
            ForEach(HabitTimeZone.options) { option in
                Button {
                    store.defaultTimeZoneIdentifier = option.identifier
                } label: {
                    let title = "\(option.identifier) · \(option.offset)"
                    if store.defaultTimeZoneIdentifier == option.identifier {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            AppSettingsRow(title: String(localized: "Standardzeitzone"),
                           detail: HabitTimeZone.displayName(for: store.defaultTimeZoneIdentifier),
                           symbol: "globe") {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(.primary)
        .accessibilityLabel(String(localized: "Standardzeitzone"))
        .accessibilityIdentifier("default-timezone-picker")
    }

    // Die Statistik-Karten-Auswahl stand hier (bis zu zwei Karten über der
    // Habit-Liste). Die Karten wohnen jetzt vollzählig im eigenen
    // Statistik-Tab — es gibt nichts mehr auszuwählen. `StatsCardPrefs`
    // bleibt als Datenformat bestehen (alte Dateien und iCloud-Stände
    // decodieren unverändert), nur die Oberfläche dazu ist weg.

    private var swipeActionsSection: some View {
        AppSettingsGroup(title: String(localized: "Wischaktionen")) {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
                Toggle(isOn: Binding(
                    get: { statsCards.preferences.swipeActions.enabled },
                    set: { enabled in
                        statsCards.update { $0.swipeActions.enabled = enabled }
                    })) {
                    AppSettingsRow(title: String(localized: "Wischaktionen"),
                                   symbol: "hand.draw") {
                        EmptyView()
                    }
                }
                .accessibilityIdentifier("swipe-actions-toggle")

                if statsCards.preferences.swipeActions.enabled {
                    Picker(String(localized: "Nach rechts wischen"), selection: swipeLeadingBinding) {
                        ForEach(SwipeActionChoice.selectable) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("swipe-leading-picker")

                    Picker(String(localized: "Nach links wischen"), selection: swipeTrailingBinding) {
                        ForEach(SwipeActionChoice.selectable) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("swipe-trailing-picker")
                }
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    /// Die Altlasten `primary`/`secondary` lesen sich als „keine
    /// Extra-Aktion" — genau so löst ContentView sie auch auf.
    private func normalized(_ choice: SwipeActionChoice) -> SwipeActionChoice {
        SwipeActionChoice.selectable.contains(choice) ? choice : .none
    }

    private var swipeLeadingBinding: Binding<SwipeActionChoice> {
        Binding(get: { normalized(statsCards.preferences.swipeActions.leading) },
                set: { choice in statsCards.update { $0.swipeActions.leading = choice } })
    }

    private var swipeTrailingBinding: Binding<SwipeActionChoice> {
        Binding(get: { normalized(statsCards.preferences.swipeActions.trailing) },
                set: { choice in statsCards.update { $0.swipeActions.trailing = choice } })
    }
}
