import SwiftUI

extension MoreView {
    /// Sync status is useful while editing integration behavior, but does not
    /// belong on the More hub where it becomes permanent ambient noise.
    /// The local sentence model: which one, whether it is on the phone, and how
    /// much room it takes.
    ///
    /// This is here and not in Darstellung because it is not how the app looks —
    /// it is which model the app thinks with, and the weights for it are the only
    /// thing in the app that can take a gigabyte.
    var localModelSettings: some View {
        // Same shell as every other settings page: the group IS the surface.
        //
        // This used to add padding and a second panel around
        // `localModelSection` as well — but `localModelSection` is an
        // `AppSettingsGroup`, which paints its own. That gave the page a panel
        // inside a panel, pulled the group's label and footer INTO the outer one
        // where the component puts them outside, and dropped the gutter that
        // every sibling page uses.
        // The heading is still dropped, because the navigation bar names the page.
        SettingsPage {
            AppSettingsGroup(title: String(localized: "Aus einem Satz anlegen"),
                             footer: String(localized: "Datums- und Zeitangaben funktionieren ohne Download. Zusätzliche Unterstützung ist optional und bleibt auf dem Gerät.")) {
                AppSettingsRow(title: String(localized: "Zusätzliche Unterstützung"),
                               detail: String(localized: "Automatische Auswahl"),
                               symbol: "sparkles") {
                    if OnDeviceModel.isAvailable || LocalModelCatalogue.all.contains(where: {
                        modelService.registry.state(for: $0.id).isReady
                    }) {
                        Text(String(localized: "Bereit"))
                            .foregroundStyle(.secondary)
                    } else {
                        modelControl(LocalModelCatalogue.default,
                                     state: modelService.registry.state(for: LocalModelCatalogue.default.id))
                    }
                }
            }
            DisclosureGroup {
                localModelSection
            } label: {
                AppSettingsRow(title: String(localized: "Erweiterte Modellauswahl"),
                               symbol: "slider.horizontal.3") { EmptyView() }
            }
            .accessibilityIdentifier("local-model-advanced")
        }
        .onAppear { modelService.refresh() }
        // Without this the last line of the footnote sits flush against the
        // bottom edge and is cut in half, which reads as a layout fault rather
        // than as a scroll that could continue.
        .safeAreaPadding(.bottom, 24)
    }

    /// The catalogue, built from the same components as every other settings
    /// page.
    ///
    /// This was hand-laid-out the first time: a bare panel with hand-built rows
    /// and rules between them. It used the same surface, so the material was
    /// right, but it did not look like a settings page — no group label, no row
    /// indentation, none of the shared row treatment. Everything here goes
    /// through AppSettingsGroup and AppSettingsRow for that reason, so the page
    /// changes with the appearance setting the way every other page does.
    private var localModelSection: some View {
        AppSettingsGroup(
            title: String(localized: "Welches Modell deinen Satz liest"),
            footer: String(localized: "Modelle bleiben auf diesem Gerät und werden nicht über iCloud übertragen. Beim ersten Lesen braucht das Modell ein paar Sekunden, bis es geladen ist.")) {
            ForEach(Array(LocalModelCatalogue.all.enumerated()), id: \.element.id) { index, model in
                if index > 0 { Divider() }
                localModelRow(model)
            }
        }
        .accessibilityIdentifier("local-model-group")
    }

    private func localModelRow(_ model: LocalModelDescriptor) -> some View {
        let state = modelService.registry.state(for: model.id)
        let isSelected = modelService.selectedModelID == model.id

        return AppSettingsRow(
            title: model.displayName,
            // Size first: it is the fact that decides, the summary is the reason.
            detail: "\(model.formattedSize) · \(model.summary)",
            symbol: Self.symbol(for: model),
            trailing: {
                HStack(spacing: 10) {
                    selectionControl(model, isSelected: isSelected)
                    modelControl(model, state: state)
                }
            })
            .accessibilityIdentifier("local-model-\(model.id)")
    }

    /// The choice, as an explicit control rather than "tap anywhere on the row".
    ///
    /// With the row itself as the target, a scroll that grazed a row put a
    /// checkmark on that model: the whole row was the selection, so anything that
    /// landed on it counted. A control that is only pressed when pressed cannot
    /// do that, and it is also how a radio list is expected to behave.
    @ViewBuilder
    private func selectionControl(_ model: LocalModelDescriptor,
                                  isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(accentColor)
                .accessibilityLabel(String(localized: "Ausgewählt"))
        } else {
            Button {
                modelService.selectedModelID = model.id
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "\(model.displayName) auswählen"))
            .accessibilityIdentifier("local-model-select-\(model.id)")
        }
    }

    /// One glyph per kind, so the list can be scanned rather than read.
    private static func symbol(for model: LocalModelDescriptor) -> String {
        switch model.scope {
        case .processing: return "bolt.fill"
        case .language: return "textformat"
        case .multilingual: return "globe"
        }
    }

    @ViewBuilder
    private func modelControl(_ model: LocalModelDescriptor, state: LocalModelState) -> some View {
        switch state {
        case .notDownloaded:
            Button {
                Task { await modelService.download(model) }
            } label: {
                Text(modelService.canFit(model)
                     ? String(localized: "Laden")
                     : String(localized: "Zu wenig Speicher"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!modelService.canFit(model))
            .accessibilityIdentifier("local-model-download-\(model.id)")

        case .downloading(let received, _):
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: state.fraction ?? 0)
                    .progressViewStyle(.linear)
                    .frame(width: 84)
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: received, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Abbrechen")) { modelService.cancel(model) }
                        .font(.caption2)
                }
            }
            .accessibilityIdentifier("local-model-progress-\(model.id)")

        case .ready:
            Button(role: .destructive) {
                modelService.delete(model)
            } label: {
                Text(String(localized: "Entfernen"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("local-model-delete-\(model.id)")

        case .failed(let reason):
            VStack(alignment: .trailing, spacing: 3) {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Erneut")) {
                    Task { await modelService.download(model) }
                }
                .font(.caption2)
            }
            .accessibilityIdentifier("local-model-failed-\(model.id)")
        }
    }
}
