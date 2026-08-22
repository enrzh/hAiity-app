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
        List {
            Section {
                Button {
                    selection = nil
                } label: {
                    zoneRow(symbol: "arrow.triangle.branch",
                            title: inheritedLabel,
                            subtitle: String(localized: "Vom Standard übernehmen"),
                            selected: selection == nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timezone-inherit")

                if allowsDeviceOverride {
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

            Section {
                ForEach(filteredOptions) { option in
                    Button {
                        selection = option.identifier
                    } label: {
                        zoneRow(symbol: "globe",
                                title: option.name,
                                subtitle: option.offset + " · " + option.identifier,
                                selected: selection == option.identifier)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(timezoneIdentifier(for: option.identifier))
                }
            }
        }
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: String(localized: "Zeitzone suchen"))
        .listStyle(.insetGrouped)
    }

    private func zoneRow(symbol: String,
                         title: String,
                         subtitle: String,
                         selected: Bool) -> some View {
        HStack(spacing: Theme.Metrics.gap) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Theme.accentText() : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Metrics.gap)
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText())
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
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
                .navigationTitle(String(localized: "Zeitzone"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Fertig")) { dismiss() }
                    }
                }
        }
    }
}
