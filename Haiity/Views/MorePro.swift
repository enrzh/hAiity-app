import SwiftUI

extension MoreView {
    // MARK: – hAiity Pro
    //
    // Steht direkt unter dem iCloud-Status und spricht dessen Sprache:
    // Symbolkachel, Titel, ein Satz. Und unmittelbar DARUNTER stehen die drei
    // Zeilen, die davon abhängen (Icon per Farbrad, eigene Farbe, Kalender) —
    // wer hier kauft, sieht das Ergebnis, ohne zu scrollen.
    //
    // Der Markenname bleibt unübersetzt (`verbatim`): er steht in keinem
    // Katalog und darf in keiner Sprache anders heissen.

    var proSection: some View {
        AppSettingsGroup(title: String(localized: "hAiity Pro")) {
            if unlocked {
                Button {
                    paywall = .settings
                } label: {
                    HStack(spacing: Theme.Metrics.gap) {
                        proRow(symbol: "checkmark.seal.fill",
                               detail: String(localized: "Freigeschaltet. Danke."),
                               highlighted: true)
                            .accessibilityIdentifier("pro-status")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("open-pro-details")
            } else {
                Button {
                    paywall = .settings
                } label: {
                    HStack(spacing: Theme.Metrics.gap) {
                        proRow(symbol: "lock",
                               detail: String(localized: "Mehr Habits, Farben, Kalender und Statistik."),
                               highlighted: false)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("open-paywall")
            }
        }
    }

    /// Dieselbe Form wie die iCloud-Zeile darüber — zwei Statuszeilen
    /// untereinander, die sich unterscheiden, lesen sich wie ein Bruch.
    private func proRow(symbol: String, detail: String, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(highlighted ? AnyShapeStyle(Theme.accentFill(palettes.style))
                                        : AnyShapeStyle(Color.secondary),
                            in: RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "hAiity Pro")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(highlighted ? AnyShapeStyle(Theme.accentText(palettes.style))
                                                 : AnyShapeStyle(HierarchicalShapeStyle.primary))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Das eine Schloss-Zeichen gegateter Zeilen. Es sagt VOR dem Tippen, was
    /// passiert — ein Schalter, der wortlos zurückspringt, wirkt kaputt.
    var proLock: some View {
        Image(systemName: "lock")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Nur mit hAiity Pro"))
    }
}
