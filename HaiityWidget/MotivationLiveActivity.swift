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
                    Image(systemName: "sparkles")
                        .foregroundStyle(MotivationActivityStyle.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: "hAiity")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Text(context.attributes.body)
                            .font(.subheadline)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(intent: DismissMotivationActivityIntent()) {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(MotivationActivityStyle.accent)
            } compactTrailing: {
                Text(verbatim: "hAiity")
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(MotivationActivityStyle.accent)
            }
        }
    }
}

private enum MotivationActivityStyle {
    static let accent = Theme.accentText(PaletteStyle.default)
}

private struct MotivationLockScreenView: View {
    let context: ActivityViewContext<MotivationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(MotivationActivityStyle.accent)
                Text(verbatim: "hAiity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(String(localized: "Heute"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(context.attributes.title)
                .font(.headline)
                .lineLimit(2)

            Text(context.attributes.body)
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(intent: DismissMotivationActivityIntent()) {
                Label(String(localized: "Ausblenden"), systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(MotivationActivityStyle.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("motivation-activity")
    }
}
