import ActivityKit
import SwiftUI
import WidgetKit

struct MotivationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MotivationActivityAttributes.self) { context in
            MotivationLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(verbatim: "hAiity")
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(MotivationActivityStyle.accent)
                    }
                    .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MotivationDismissButton()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: context.attributes.title)
                            .font(.headline)
                            .lineLimit(2)
                            .privacySensitive()
                        Text(verbatim: context.attributes.body)
                            .font(.subheadline)
                            .lineLimit(2)
                            .privacySensitive()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(MotivationActivityStyle.accent)
            } compactTrailing: {
                Text(verbatim: "hAiity")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(MotivationActivityStyle.accent)
            }
            .widgetURL(HaiityWidgetLink.habits)
            .keylineTint(MotivationActivityStyle.accent)
        }
    }
}

private enum MotivationActivityStyle {
    static let accent = Theme.accentText(PaletteStyle.default)
}

private struct MotivationDismissButton: View {
    var body: some View {
        Button(intent: DismissMotivationActivityIntent()) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel(String(localized: "Ausblenden"))
        .accessibilityIdentifier("motivation-dismiss")
    }
}

private struct MotivationLockScreenView: View {
    let context: ActivityViewContext<MotivationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(verbatim: "hAiity")
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(MotivationActivityStyle.accent)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Text(verbatim: context.attributes.title)
                        .font(.headline)
                        .lineLimit(2)
                        .privacySensitive()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MotivationDismissButton()
            }

            Text(verbatim: context.attributes.body)
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitive()
        }
        .padding(14)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(MotivationActivityStyle.accent)
        .widgetURL(HaiityWidgetLink.habits)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("motivation-activity")
    }
}
