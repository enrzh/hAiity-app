import SwiftUI

/// Shared, searchable timezone list used by the global setting and by the
/// habit editor. The selection stays optional so nil remains the one meaning
/// of "inherit the default" in habit data.
struct HabitTimeZoneList: View {
    @Binding var selection: String?
    let inheritedLabel: String
    let allowsDeviceOverride: Bool

    @State private var query = ""

    private var filteredOptions: [HabitTimeZoneOption] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return HabitTimeZone.options }
        return HabitTimeZone.options.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.identifier.localizedCaseInsensitiveContains(needle)
                || $0.offset.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        // Not a `List`: iOS 27 drops taps on grouped list rows, and this page is
        // a long tappable list of time zones. Same group surface as the hub.
        ScrollView {
            VStack(spacing: Theme.Metrics.settingsSectionGap) {
                AppSettingsGroup(title: String(localized: "Standard")) {
                    Button {
                        selection = nil
                    } label: {
                        zoneRow(symbol: "arrow.triangle.branch",
                                title: inheritedLabel,
                                subtitle: allowsDeviceOverride
                                    ? String(localized: "Vom Standard übernehmen")
                                    : TimeZone.current.identifier,
                                selected: selection == nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timezone-inherit")

                    if allowsDeviceOverride {
                        zoneDivider
                        Button {
                            selection = HabitTimeZone.deviceIdentifier
                        } label: {
                            zoneRow(symbol: "iphone",
                                    title: String(localized: "Gerätezeitzone"),
                                    subtitle: TimeZone.current.identifier,
                                    selected: selection == HabitTimeZone.deviceIdentifier)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("timezone-device")
                    }
                }

                AppSettingsGroup(title: String(localized: "Zeitzonen")) {
                    ForEach(Array(filteredOptions.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { zoneDivider }
                        Button {
                            selection = option.identifier
                        } label: {
                            zoneRow(symbol: "globe",
                                    title: option.identifier.split(separator: "/").last.map(String.init)?
                                        .replacingOccurrences(of: "_", with: " ") ?? option.name,
                                    subtitle: option.offset + " · " + option.name,
                                    selected: selection == option.identifier)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(timezoneIdentifier(for: option.identifier))
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: String(localized: "Zeitzone suchen"))
        .settingsChrome()
    }

    /// Inset to the text edge, matching the hub's grouped rows.
    private var zoneDivider: some View {
        Divider().padding(.leading, Theme.Metrics.gap)
    }

    private func zoneRow(symbol: String,
                         title: String,
                         subtitle: String,
                         selected: Bool) -> some View {
        HStack(spacing: Theme.Metrics.gap) {
            if symbol != "globe" {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Metrics.gap)
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText())
            }
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        .padding(.vertical, 3)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func timezoneIdentifier(for value: String) -> String {
        "timezone-" + value.replacingOccurrences(of: "/", with: "-")
    }
}

struct HabitTimeZoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String?
    let inheritedLabel: String

    var body: some View {
        NavigationStack {
            HabitTimeZoneList(selection: $selection,
                              inheritedLabel: inheritedLabel,
                              allowsDeviceOverride: true)
                .appPageHeader(String(localized: "Zeitzone"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Fertig")) { dismiss() }
                    }
                }
        }
    }
}
