import SwiftUI
import UIKit

extension MoreView {
    var notificationActionsSection: some View {
        AppSettingsGroup(title: String(localized: "Mitteilungen")) {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
                Toggle(isOn: Binding(
                    get: { statsCards.preferences.notificationActionsEnabled },
                    set: { enabled in
                        statsCards.update { $0.notificationActionsEnabled = enabled }
                        NotificationPresenter.configureQuickActions(
                            enabled: enabled,
                            choices: statsCards.preferences.notificationActions.slots)
                    })) {
                    AppSettingsRow(title: String(localized: "Schnellaktionen in Mitteilungen"),
                                   symbol: "bell.badge") {
                        EmptyView()
                    }
                }
                .accessibilityIdentifier("notification-actions-toggle")

                if statsCards.preferences.notificationActionsEnabled {
                    ForEach(0..<NotificationActionPreferences.slotCount, id: \.self) { index in
                        Picker(notificationSlotTitle(index),
                               selection: notificationActionBinding(at: index)) {
                            ForEach(statsCards.preferences.notificationActions
                                .availableChoices(for: index)) { choice in
                                Text(choice.notificationDisplayName).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("notification-action-picker-\(index + 1)")
                    }
                    notificationActionsPreview
                }
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    private func notificationSlotTitle(_ index: Int) -> String {
        switch index {
        case 0: return String(localized: "Hauptaktion")
        case 1: return String(localized: "Zweite Aktion")
        default: return String(localized: "Dritte Aktion")
        }
    }

    private var notificationActionsPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "Vorschau"), systemImage: "bell")
                .font(.footnote.weight(.semibold))
            notificationPreviewRow(String(localized: "Abhaken"), base: .checkbox)
            notificationPreviewRow(String(localized: "Menge"), base: .quantity)
            notificationPreviewRow(String(localized: "Ja/Nein"), base: .yesNo)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("notification-actions-preview")
    }

    private func notificationPreviewRow(_ title: String,
                                        base: NotificationQuickAction) -> some View {
        let actions = NotificationQuickAction.actions(
            for: base,
            choices: statsCards.preferences.notificationActions.slots)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(actions.isEmpty
                 ? String(localized: "Keine Aktion")
                 : actions.map(\.title).joined(separator: " · "))
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func notificationActionBinding(at index: Int) -> Binding<SwipeActionChoice> {
        Binding(
            get: { statsCards.preferences.notificationActions[index] },
            set: { choice in updateNotificationAction(at: index, to: choice) })
    }

    private func updateNotificationAction(at index: Int, to choice: SwipeActionChoice) {
        var next = statsCards.preferences
        next.notificationActions.assign(choice, to: index)
        statsCards.update { $0.notificationActions = next.notificationActions }
        NotificationPresenter.configureQuickActions(
            enabled: next.notificationActionsEnabled,
            choices: next.notificationActions.slots)
    }

    // MARK: – Mitteilungen
    //
    // Tages- und Wochenzusammenfassung tragen den Stand, die Motivation
    // einen ruhigen Satz aus dem lokalen Vorrat. Alle drei bleiben getrennt:
    // wer Zahlen will, will nicht automatisch einen Gedanken dazu — und
    // jede Meldung darf zu ihrer eigenen Uhrzeit kommen.
    //
    // Das Berechtigungs-Gate bleibt exakt wie gehabt: gefragt wird NUR beim
    // aktiven Einschalten, nie beim Start.

    var notificationSettingsSection: some View {
        VStack(spacing: store.appearancePreferences.designStyle.sectionGap) {
            AppSettingsGroup(title: String(localized: "Ruhezeiten")) {
                notificationOptOutRows
                    .notificationSettingsRow()
            }

            AppSettingsGroup(title: String(localized: "Tagesmeldung")) {
                dailySummaryRows
                    .notificationSettingsRow()
            }

            AppSettingsGroup(title: String(localized: "Wochensumme")) {
                weeklySummaryRows
                    .notificationSettingsRow()
            }

            AppSettingsGroup(title: String(localized: "Motivation")) {
                motivationRows
                    .notificationSettingsRow()
            }
        }
    }

    private var notificationDetailsInset: CGFloat {
        Theme.Metrics.glyph + Theme.Metrics.gap + 4
    }

    private var notificationOptOutRows: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
            Toggle(isOn: dndEnabled) {
                notificationLabel(NotificationDNDPresentation.title,
                                  symbol: NotificationDNDPresentation.symbolName)
            }
                .accessibilityIdentifier("dnd-toggle")
            if dndActive {
                Picker(String(localized: "Dauer"), selection: dndModeBinding) {
                    ForEach(dndModes, id: \.self) { mode in
                        Text(dndTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("dnd-duration-picker")
                .padding(.leading, notificationDetailsInset)
                if notificationDND.mode == .custom {
                    DatePicker(String(localized: "Bis"), selection: dndCustomDateBinding,
                               in: Date().addingTimeInterval(60)...)
                        .accessibilityIdentifier("dnd-custom-date")
                        .padding(.leading, notificationDetailsInset)
                }
                Text(dndEndText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, notificationDetailsInset)
            }
        }
        .padding(.vertical, Theme.Metrics.gap / 2)
    }

    private var dndActive: Bool { notificationDND.isActive() }

    private var dndModes: [NotificationDNDState.Mode] {
        [.twoHours, .eightHours, .twentyFourHours, .custom, .untilDisabled]
    }

    private var dndEnabled: Binding<Bool> {
        Binding(
            get: { dndActive },
            set: { enabled in
                applyDND(enabled
                         ? .active(.twoHours)
                         : .off)
            })
    }

    private var dndModeBinding: Binding<NotificationDNDState.Mode> {
        Binding(
            get: { dndActive ? notificationDND.mode : .twoHours },
            set: { mode in
                if mode == .custom {
                    if dndCustomDate <= .now {
                        dndCustomDate = .now.addingTimeInterval(2 * 60 * 60)
                    }
                    applyDND(.active(.custom, customUntil: dndCustomDate))
                } else {
                    applyDND(.active(mode))
                }
            })
    }

    private var dndCustomDateBinding: Binding<Date> {
        Binding(
            get: { dndCustomDate },
            set: { date in
                dndCustomDate = date
                guard notificationDND.mode == .custom else { return }
                applyDND(.active(.custom, customUntil: date))
            })
    }

    private func dndTitle(_ mode: NotificationDNDState.Mode) -> String {
        switch mode {
        case .off: return String(localized: "Aus")
        case .twoHours: return String(localized: "2 Stunden")
        case .eightHours: return String(localized: "8 Stunden")
        case .twentyFourHours: return String(localized: "24 Stunden")
        case .custom: return String(localized: "Benutzerdefiniert")
        case .untilDisabled: return String(localized: "Bis ausgeschaltet")
        }
    }

    private var dndEndText: String {
        if let until = notificationDND.until {
            let remaining = max(0, Int(until.timeIntervalSince(dndNow)))
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            let remainingText: String
            if hours > 0 {
                remainingText = String.localizedStringWithFormat(
                    String(localized: "Noch %d Std. %d Min."), hours, minutes)
            } else {
                remainingText = String.localizedStringWithFormat(
                    String(localized: "Noch %d Min."), max(1, minutes))
            }
            return String(localized: "Aktiv bis") + " "
                + until.formatted(date: .omitted, time: .shortened)
                + " · " + remainingText
        }
        return String(localized: "Aktiv bis Nicht stören ausgeschaltet wird")
    }

    private func applyDND(_ state: NotificationDNDState) {
        notificationDND = state
        NotificationPromptPreference.state = state
        updateCloudPreferences { $0.notificationDND = state }
        Task {
            await Reminders.reschedule(store: store)
        }
    }

    private var dailySummaryRows: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
            Toggle(isOn: dailyEnabled) {
                notificationLabel(String(localized: "Tageszusammenfassung"),
                                  symbol: "sun.max")
            }
            .disabled(dndActive)
            .accessibilityIdentifier("summary-toggle")
            if store.summaryMinutes != nil {
                DatePicker(String(localized: "Uhrzeit"),
                           selection: dailyTime,
                           displayedComponents: .hourAndMinute)
                    .padding(.leading, notificationDetailsInset)
                    .accessibilityIdentifier("summary-time")
            }
            if summaryDenied { permissionHint }
        }
        .padding(.vertical, Theme.Metrics.gap / 2)
    }

    private var weeklySummaryRows: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
            Toggle(isOn: weeklyEnabled) {
                notificationLabel(String(localized: "Wochenzusammenfassung"),
                                  symbol: "calendar")
            }
            .disabled(dndActive)
            .accessibilityIdentifier("weekly-summary-toggle")
            if store.weeklySummaryMinutes != nil {
                weeklyWeekdayButton
                DatePicker(String(localized: "Uhrzeit"),
                           selection: weeklyTime,
                           displayedComponents: .hourAndMinute)
                    .padding(.leading, notificationDetailsInset)
                    .accessibilityIdentifier("weekly-summary-time")
            }
            if weeklyDenied { permissionHint }
        }
        .padding(.vertical, Theme.Metrics.gap / 2)
    }

    /// Keep the selector's button intrinsic-sized. A flexible Menu label in a
    /// single iOS 27 List row can inherit the hit region of the whole group.
    private var weeklyWeekdayButton: some View {
        HStack(spacing: Theme.Metrics.gap + 2) {
            Text(String(localized: "Wochentag"))
            Spacer(minLength: Theme.Metrics.gap)
            Button {
                showWeeklyWeekdayPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(RecurrenceText.weekdayName(store.weeklySummaryWeekday))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.tint)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("weekly-summary-weekday")
            .confirmationDialog(String(localized: "Wochentag auswählen"),
                                isPresented: $showWeeklyWeekdayPicker,
                                titleVisibility: .visible) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    Button {
                        weeklyWeekday.wrappedValue = day
                    } label: {
                        let title = RecurrenceText.weekdayName(day)
                        if day == store.weeklySummaryWeekday {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
                Button(String(localized: "Abbrechen"), role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity,
               minHeight: Theme.Metrics.hit,
               alignment: .leading)
        .padding(.leading, notificationDetailsInset)
    }

    private var motivationRows: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
            Toggle(isOn: motivationEnabled) {
                notificationLabel(String(localized: "Tägliche Motivation"),
                                  symbol: "quote.bubble")
            }
            .disabled(dndActive)
            .accessibilityIdentifier("motivation-toggle")
            if store.motivationMinutes != nil {
                VStack(alignment: .leading, spacing: Theme.Metrics.gap + 2) {
                    DatePicker(String(localized: "Uhrzeit"),
                               selection: motivationTime,
                               displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("motivation-time")
                    Picker(String(localized: "Darstellung"), selection: motivationDelivery) {
                        ForEach(MotivationDelivery.allCases, id: \.self) { delivery in
                            Text(delivery.displayName).tag(delivery)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("motivation-delivery")
                    if store.motivationDelivery == .liveActivity {
                        Text(String(localized: "Live-Aktivitäten starten, sobald hAiity einmal geöffnet wurde."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    motivationSourceControl
                }
                .padding(.leading, notificationDetailsInset)
            }
            if motivationDenied { permissionHint }
        }
        .padding(.vertical, Theme.Metrics.gap / 2)
    }

    /// Fixed on purpose: the slot is `Theme.Metrics.glyph`, so a Dynamic-Type
    /// font would let the glyph overflow its own background at AX5.
    private func notificationSymbolSurface(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(currentAppearance.designStyle.usesQuietSurfaces
                             ? Color.primary : Theme.accentText(palettes.style))
            .frame(width: Theme.Metrics.glyph,
                   height: Theme.Metrics.glyph)
            .background(
                Theme.accentText(palettes.style).opacity(currentAppearance.designStyle.usesQuietSurfaces ? 0 : 0.12),
                in: RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
            .accessibilityHidden(true)
    }

    /// No `lineLimit` and no `minimumScaleFactor`: at AX5 the toggle label has
    /// to wrap. Shrinking or truncating it was clipping "Do not disturb" to
    /// "Do not dist…", which the design system's accessibility floor forbids.
    private func notificationLabel(_ title: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.gap + 4) {
            notificationSymbolSurface(symbol)
            Text(title)
                .font(currentAppearance.designStyle.rowTitleFont)
                .fixedSize(horizontal: false, vertical: true)
        }
    }



    /// Where the daily line comes from: the translated pool, or a fresh line
    /// from the on-device model.
    ///
    /// The model row is only offered when the model can actually run. An
    /// ineligible device gets the pool and an honest reason, never a control
    /// that silently does nothing — and never the retired network feed, which is
    /// why the source is a choice between two things the app owns.
    private var motivationSourceControl: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Picker(String(localized: "Quelle"), selection: motivationSourceBinding) {
                ForEach(Motivation.Source.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("motivation-source-picker")

            Text(motivationSourceCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Indented to the title edge like every other caption, so the
                // detail reads as belonging to the row it explains.
                .padding(.leading, Theme.Metrics.glyph + Theme.Metrics.gap + 4)
                .fixedSize(horizontal: false, vertical: true)

            if store.motivationSource == .onDevice {
                motivationWriteControl
            }
        }
        .padding(.leading, -notificationDetailsInset)
        .padding(.top, 2)
    }

    /// The explicit "write me a sentence" action.
    ///
    /// Nothing here runs on its own. The scheduler only reads what a tap has
    /// already written, so a day without a tap gets the built-in line — which
    /// is the same thing an unavailable model would produce, just cheaper.
    @ViewBuilder
    private var motivationWriteControl: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            if motivationIsWriting {
                HStack(spacing: Theme.Metrics.gap) {
                    ProgressView()
                    Text(String(localized: "Schreibt einen Satz…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let written = motivationWrittenLine {
                Text(written)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Anderer Satz")) {
                    writeMotivationLine(reroll: true)
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityIdentifier("motivation-reroll")
            } else {
                Button(String(localized: "Satz schreiben")) {
                    writeMotivationLine(reroll: false)
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityIdentifier("motivation-write")

                if motivationWriteFailed {
                    // The built-in line is what today's notification will use,
                    // so say that rather than implying the message is missing.
                    Text(String(localized: "Hat nicht geklappt – heute gilt der integrierte Satz."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("motivation-write-failed")
                }
            }
        }
        .padding(.top, 2)
    }

    private var motivationWrittenLine: String? {
        MotivationDaily.cachedLine(for: DayKey.today(), in: SharedStorage.defaults)
    }

    /// Write today's line because the person asked. A repeat tap without a
    /// re-roll returns the cached line instead of paying for a second call.
    private func writeMotivationLine(reroll: Bool) {
        motivationIsWriting = true
        motivationWriteFailed = false
        Task {
            let language = Locale.current.language.languageCode?.identifier ?? "en"
            let line = await MotivationDaily.rerollOrWriteLine(
                for: DayKey.today(), language: language,
                reroll: reroll, defaults: SharedStorage.defaults)
            await MainActor.run {
                motivationIsWriting = false
                motivationWriteFailed = line == nil
            }
            // The scheduled notification carries the day's text, so it has to be
            // re-planned or today's line stays the built-in one until the next
            // unrelated settings change.
            await Reminders.reschedule(store: store)
            await MotivationActivityManager.shared.reconcile(
                motivationMinutes: store.motivationMinutes,
                name: PersonalName.effective,
                delivery: store.motivationDelivery,
                source: store.motivationSource)
        }
    }

    private var motivationSourceCaption: String {
        switch OnDeviceModel.availability {
        case .available:
            return String(localized: "Jeder Tag ein neuer Satz, geschrieben auf diesem Gerät. Bleibt offline und wird nicht mitgesendet.")
        case .appleIntelligenceOff:
            return String(localized: "Apple Intelligence ist aus. Schalte sie in den iOS-Einstellungen ein, um eigene Sätze zu erhalten.")
        case .modelNotReady:
            return String(localized: "Das Modell lädt noch. Bis dahin kommen die integrierten Sätze.")
        case .deviceNotEligible:
            return String(localized: "Dieses Gerät kann das On-Device-Modell nicht ausführen. Die integrierten Sätze bleiben aktiv.")
        case .unsupportedSystem:
            return String(localized: "Eigene Sätze brauchen iOS 26. Die integrierten Sätze bleiben aktiv.")
        }
    }

    /// Only the sources that can actually run are selectable. If the model
    /// becomes unavailable after it was chosen, the stored choice stays but the
    /// pool serves the message — losing the setting on a later launch would be
    /// worse than quietly honouring it when it comes back.
    private var selectableMotivationSources: [Motivation.Source] {
        Motivation.Source.allCases.filter {
            $0 == .builtIn || OnDeviceModel.isAvailable
        }
    }

    private var motivationSourceBinding: Binding<Motivation.Source> {
        Binding(
            get: { store.motivationSource },
            set: { source in
                store.motivationSource = source
                if source == .builtIn {
                    MotivationGeneratedStore.clear(in: SharedStorage.defaults)
                }
                Task {
                    await Reminders.reschedule(store: store)
                    await MotivationActivityManager.shared.reconcile(
                        motivationMinutes: store.motivationMinutes,
                        name: PersonalName.effective,
                        delivery: store.motivationDelivery,
                        source: store.motivationSource)
                }
            })
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert."))
                .font(.caption)
                .foregroundStyle(.orange)
            // Der direkte Sprung statt einer Wegbeschreibung: iOS öffnet die
            // Mitteilungs-Einstellungen DIESER App.
            Button(String(localized: "iOS-Einstellungen öffnen")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("open-notification-settings")
        }
    }

    /// Wochentage in der Reihenfolge des Nutzerkalenders (Mo … So in
    /// Deutschland, So … Sa in den USA).
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    /// Standardzeiten: der Tag klingt abends aus, die Woche sonntags am
    /// frühen Abend — beides nach dem letzten sinnvollen Moment, an dem man
    /// noch etwas nachholen kann.
    private static let defaultDailyMinutes = 20 * 60
    private static let defaultWeeklyMinutes = 18 * 60
    private static let defaultMotivationMinutes = 8 * 60

    private var dailyEnabled: Binding<Bool> {
        Binding(
            get: { store.summaryMinutes != nil },
            set: { on in
                guard on else { store.summaryMinutes = nil; return }
                askThen { granted in
                    if granted {
                        store.summaryMinutes = store.summaryMinutes ?? Self.defaultDailyMinutes
                        summaryDenied = false
                    } else {
                        summaryDenied = true
                    }
                }
            })
    }

    private var weeklyEnabled: Binding<Bool> {
        Binding(
            get: { store.weeklySummaryMinutes != nil },
            set: { on in
                guard on else { store.weeklySummaryMinutes = nil; return }
                askThen { granted in
                    if granted {
                        store.weeklySummaryMinutes = store.weeklySummaryMinutes
                            ?? Self.defaultWeeklyMinutes
                        weeklyDenied = false
                    } else {
                        weeklyDenied = true
                    }
                }
            })
    }

    private var motivationEnabled: Binding<Bool> {
        Binding(
            get: { store.motivationMinutes != nil },
            set: { on in
                guard on else { store.motivationMinutes = nil; return }
                if store.motivationDelivery == .liveActivity {
                    store.motivationMinutes = store.motivationMinutes
                        ?? Self.defaultMotivationMinutes
                    motivationDenied = false
                    return
                }
                askThen { granted in
                    if granted {
                        store.motivationMinutes = store.motivationMinutes
                            ?? Self.defaultMotivationMinutes
                        motivationDenied = false
                    } else {
                        motivationDenied = true
                    }
                }
            })
    }

    private var motivationDelivery: Binding<MotivationDelivery> {
        Binding(
            get: { store.motivationDelivery },
            set: { delivery in
                guard delivery != store.motivationDelivery else { return }
                guard delivery == .notification, store.motivationMinutes != nil else {
                    store.motivationDelivery = delivery
                    return
                }
                askThen { granted in
                    if granted {
                        store.motivationDelivery = delivery
                        motivationDenied = false
                    } else {
                        motivationDenied = true
                    }
                }
            })
    }

    /// Das Gate an EINER Stelle: fragen, dann auf dem Hauptthread entscheiden.
    private func askThen(_ body: @escaping @MainActor (Bool) -> Void) {
        Task {
            let granted = await Reminders.ensurePermission()
            await MainActor.run { body(granted) }
        }
    }

    private var dailyTime: Binding<Date> {
        timeBinding(get: { store.summaryMinutes ?? Self.defaultDailyMinutes },
                    set: { store.summaryMinutes = $0 })
    }

    private var weeklyTime: Binding<Date> {
        timeBinding(get: { store.weeklySummaryMinutes ?? Self.defaultWeeklyMinutes },
                    set: { store.weeklySummaryMinutes = $0 })
    }

    private var motivationTime: Binding<Date> {
        timeBinding(get: { store.motivationMinutes ?? Self.defaultMotivationMinutes },
                    set: { store.motivationMinutes = $0 })
    }

    private var weeklyWeekday: Binding<Int> {
        Binding(get: { store.weeklySummaryWeekday },
                set: { store.weeklySummaryWeekday = $0 })
    }

    /// Minuten seit Mitternacht <-> Datum. Zweimal dieselbe Rechnung wäre
    /// zweimal dieselbe Gelegenheit, sie unterschiedlich zu runden.
    private func timeBinding(get minutes: @escaping () -> Int,
                             set store: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let m = minutes()
                return Calendar.current.date(from: DateComponents(hour: m / 60,
                                                                  minute: m % 60)) ?? .now
            },
            set: { date in
                store(Calendar.current.component(.hour, from: date) * 60
                      + Calendar.current.component(.minute, from: date))
            })
    }
}

private extension View {
    /// Keep each notification group as one native List row. Nested controls
    /// inside a single List row can otherwise inherit the row's full hit area.
    func notificationSettingsRow() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Metrics.gap / 2)
    }
}

