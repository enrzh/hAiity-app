import SwiftUI
import UIKit

extension MoreView {
    // MARK: – Kalender
    //
    // Zwei Auswahlen: Habits und Erinnerungen mit Termin erscheinen in einem eigenen
    // hAiity-Kalender — und damit in Apple Kalender und (wenn das
    // Standardkonto ein Google-Konto ist) auch in Google Kalender. Der
    // Die Nutzerwahl reist über iCloud; Berechtigung, Kalenderkennung und
    // Termine bleiben gerätelokal und werden beim Abgleich geprüft.

    var calendarSection: some View {
        AppSettingsGroup(title: String(localized: "Kalender")) {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
                calendarToggle(type: .habit,
                               title: String(localized: "Habits im Kalender"),
                               identifier: "calendar-sync-habits-toggle")
                calendarToggle(type: .reminder,
                               title: String(localized: "Erinnerungen im Kalender"),
                               identifier: "calendar-sync-reminders-toggle")
                Toggle(isOn: reminderSyncBinding) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(String(localized: "Erinnerungen mit Apple synchronisieren"),
                                  systemImage: "checklist")
                            Text(String(localized: "Ziel: hAiity Reminders"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !unlocked && !nativeReminderSyncEnabled {
                            Spacer(minLength: Theme.Metrics.gap)
                            proLock
                        }
                    }
                }
                .accessibilityIdentifier("native-reminder-sync-toggle")
                Button(role: .destructive) {
                    showNativeSyncDeleteConfirmation = true
                } label: {
                    Label(String(localized: "Native Einträge löschen"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(nativeSyncCleanupInProgress)
                .accessibilityIdentifier("delete-native-entries")
                Button {
                    cleanupNativeEntries()
                } label: {
                    Label(nativeSyncCleanupButtonTitle,
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(Theme.accentText(palettes.style))
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(nativeSyncCleanupInProgress)
                .accessibilityIdentifier("cleanup-native-entries")
                if let nativeSyncCleanupMessage {
                    Text(nativeSyncCleanupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if calendarDenied {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Der Kalender-Zugriff ist in den iOS-Einstellungen deaktiviert. Dort erlauben, dann klappt der Kalender."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button(String(localized: "iOS-Einstellungen öffnen")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("open-calendar-settings")
                    }
                }
                if reminderSyncDenied {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Der Zugriff auf Erinnerungen ist in den iOS-Einstellungen deaktiviert."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button(String(localized: "iOS-Einstellungen öffnen")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("open-reminder-settings")
                    }
                }
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    private func cleanupNativeEntries() {
        nativeSyncCleanupInProgress = true
        nativeSyncCleanupNeedsRetry = false
        nativeSyncCleanupMessage = nil
        Task { @MainActor in
            let result = await NativeSyncCleanup.run()
            if result.calendar {
                await CalendarSync.reconcile(
                    habits: store.habits,
                    defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
            }
            if result.reminders {
                await ReminderSync.reconcile(
                    habits: store.habits,
                    defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
            }
            nativeSyncCleanupNeedsRetry = result.needsRetry
            nativeSyncCleanupMessage = nativeCleanupMessage(for: result)
            nativeSyncCleanupInProgress = false
        }
    }

    func deleteNativeEntries() {
        nativeSyncCleanupInProgress = true
        nativeSyncCleanupNeedsRetry = false
        nativeSyncCleanupMessage = nil
        Task { @MainActor in
            let result = await NativeSyncCleanup.deleteAllOwnedItems()
            updateCloudPreferences {
                $0.calendarSyncHabits = false
                $0.calendarSyncReminders = false
                $0.nativeReminderSync = false
            }
            nativeSyncCleanupNeedsRetry = result.needsRetry
            nativeSyncCleanupMessage = nativeDeleteMessage(for: result)
            nativeSyncCleanupInProgress = false
        }
    }

    private var nativeSyncCleanupButtonTitle: String {
        if nativeSyncCleanupInProgress {
            return String(localized: "Einträge werden aufgeräumt …")
        }
        if nativeSyncCleanupNeedsRetry {
            return String(localized: "Aufräumen erneut versuchen")
        }
        return String(localized: "Native Einträge aufräumen")
    }

    private func nativeCleanupMessage(for result: NativeSyncCleanup.Result) -> String {
        guard result.needsRetry else {
            let destinations = nativeCleanupDestinations(for: result)
            guard !destinations.isEmpty else {
                return String(localized: "Native Einträge bereinigt und neu synchronisiert.")
            }
            return String(localized: "Native Einträge bereinigt und neu synchronisiert: \(destinations.joined(separator: ", ")).")
        }
        switch (result.calendar, result.reminders) {
        case (true, false), (false, true):
            return String(localized: "Einträge teilweise bereinigt. Prüfe die Berechtigungen und versuche es erneut.")
        case (false, false):
            return String(localized: "Native Einträge konnten nicht bereinigt werden. Prüfe die Berechtigungen und versuche es erneut.")
        case (true, true):
            let destinations = nativeCleanupDestinations(for: result)
            return String(localized: "Native Einträge bereinigt und neu synchronisiert: \(destinations.joined(separator: ", ")).")
        }
    }

    private func nativeCleanupDestinations(for result: NativeSyncCleanup.Result) -> [String] {
        var destinations: [String] = []
        if result.calendar {
            if CalendarSync.syncHabits { destinations.append("hAiity Habits") }
            if CalendarSync.syncReminders { destinations.append("hAiity Reminders") }
        }
        if result.reminders && ReminderSync.isEnabled {
            destinations.append("hAiity Reminders")
        }
        return destinations
    }

    private func nativeDeleteMessage(for result: NativeSyncCleanup.Result) -> String {
        result.succeeded
            ? String(localized: "Native Einträge gelöscht. Synchronisierung ausgeschaltet.")
            : String(localized: "Einträge konnten nicht vollständig gelöscht werden. Prüfe die Berechtigungen und versuche es erneut.")
    }

    private func calendarToggle(type: HabitItemType,
                                title: String,
                                identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: calendarBinding(for: type)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(title, systemImage: type == .habit ? "calendar.badge.plus" : "bell.badge")
                        Text(calendarDestinationText(for: type))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let enabled = calendarEnabled(for: type)
                    if !unlocked && !enabled {
                        Spacer(minLength: Theme.Metrics.gap)
                        proLock
                    }
                }
            }
            .accessibilityIdentifier(identifier)
            if unlocked && CalendarSync.hasAccess {
                Button {
                    calendarPickerType = type
                    showCalendarPicker = true
                } label: {
                    Label(String(localized: "Kalender auswählen"), systemImage: "calendar.badge.gearshape")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(type == .habit
                                         ? "calendar-sync-habits-destination"
                                         : "calendar-sync-reminders-destination")
            }
        }
    }

    private func calendarDestinationText(for type: HabitItemType) -> String {
        let actual = CalendarSync.activeCalendarTitle(isReminder: type == .reminder)
            ?? CalendarSync.destinationTitle(isReminder: type == .reminder)
        return String(format: String(localized: "Ziel: %@"), actual)
    }

    var calendarDestinationPicker: some View {
        NavigationStack {
            // Not a `List`: iOS 27 drops taps on grouped list rows, and every
            // row here is a tap target.
            SettingsPage(title: String(localized: "Kalenderziel")) {
                    AppSettingsGroup(title: String(localized: "Auswahl")) {
                        calendarOptionRow(title: String(localized: "Automatisch"),
                                          subtitle: nil,
                                          selected: CalendarSync.selectedCalendarID(
                                            isReminder: calendarPickerType == .reminder) == nil) {
                            selectCalendar(nil)
                        }
                    }

                    AppSettingsGroup(title: String(localized: "Kalenderziel")) {
                        let options = CalendarSync.writableCalendarOptions
                        if options.isEmpty {
                            Text(String(localized: "Keine schreibbaren Kalender verfügbar"))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                if index > 0 { Divider().padding(.leading, Theme.Metrics.gap) }
                                calendarOptionRow(
                                    title: option.title,
                                    subtitle: option.sourceTitle.isEmpty ? nil : option.sourceTitle,
                                    selected: CalendarSync.selectedCalendarID(
                                        isReminder: calendarPickerType == .reminder) == option.id) {
                                        selectCalendar(option.id)
                                    }
                            }
                        }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen")) {
                        showCalendarPicker = false
                    }
                }
            }
        }
        .task {
            await CalendarSync.refreshDestinationCache()
        }
    }

    /// One tappable calendar destination. The checkmark is paired with the row
    /// label, so the selection is never carried by color alone.
    private func calendarOptionRow(title: String,
                                    subtitle: String?,
                                    selected: Bool,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AppSettingsRow(title: title, detail: subtitle) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accentText(palettes.style))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectCalendar(_ id: String?) {
        CalendarSync.setSelectedCalendarID(id, isReminder: calendarPickerType == .reminder)
        Task {
            await CalendarSync.reconcile(
                habits: store.habits,
                defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        }
        showCalendarPicker = false
    }

    private func calendarEnabled(for type: HabitItemType) -> Bool {
        guard unlocked else { return false }
        if type == .habit {
            return store.cloudPreferences?.calendarSyncHabits ?? CalendarSync.syncHabits
        }
        return store.cloudPreferences?.calendarSyncReminders ?? CalendarSync.syncReminders
    }

    private var nativeReminderSyncEnabled: Bool {
        guard unlocked else { return false }
        return store.cloudPreferences?.nativeReminderSync ?? ReminderSync.isEnabled
    }

    func calendarBinding(for type: HabitItemType) -> Binding<Bool> {
        Binding(
            get: { calendarEnabled(for: type) },
            set: { on in
                guard on else {
                    if type == .habit { CalendarSync.syncHabits = false }
                    else { CalendarSync.syncReminders = false }
                    updateCloudPreferences {
                        if type == .habit { $0.calendarSyncHabits = false }
                        else { $0.calendarSyncReminders = false }
                    }
                    if CalendarSync.isEnabled {
                        Task {
                            await CalendarSync.reconcile(
                                habits: store.habits,
                                defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                        }
                    }
                    else { CalendarSync.disable() }
                    return
                }
                // AUSschalten bleibt immer frei — auch nach einer Erstattung
                // darf niemand mit einem Schalter zurückbleiben, den er nicht
                // mehr umlegen kann. Nur das EINschalten ist Pro, und es fragt
                // dann gar nicht erst nach dem Kalender-Zugriff: eine
                // Berechtigung für eine Funktion, die danach doch nicht läuft,
                // ist eine Frage unter falschem Vorwand.
                guard CalendarFeatureGate.canEnable(unlocked: unlocked) else {
                    pendingCalendarItemType = type
                    paywall = .calendar
                    return
                }
                Task {
                    let granted = await CalendarSync.requestAccess()
                    await MainActor.run {
                        calendarDenied = !granted
                        guard granted else { return }
                        if type == .habit { CalendarSync.syncHabits = true }
                        else { CalendarSync.syncReminders = true }
                        updateCloudPreferences {
                            if type == .habit { $0.calendarSyncHabits = true }
                            else { $0.calendarSyncReminders = true }
                        }
                        Task {
                            await CalendarSync.reconcile(
                                habits: store.habits,
                                defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                        }
                    }
                }
            })
    }

    var reminderSyncBinding: Binding<Bool> {
        Binding(
            get: { nativeReminderSyncEnabled },
            set: { on in
                switch NativeReminderToggleAction.action(for: on, unlocked: unlocked) {
                case .disable:
                    reminderSyncDenied = false
                    ReminderSync.disable()
                    updateCloudPreferences { $0.nativeReminderSync = false }
                case .showPaywall:
                    pendingNativeReminder = true
                    paywall = .calendar
                case .requestAccess:
                    Task {
                        let granted = await ReminderSync.requestAccess()
                        guard granted else {
                            await MainActor.run { reminderSyncDenied = true }
                            return
                        }
                        await MainActor.run {
                            reminderSyncDenied = false
                            ReminderSync.isEnabled = true
                            updateCloudPreferences { $0.nativeReminderSync = true }
                            ReminderSync.startObserving(store: store)
                        }
                        await ReminderSync.reconcile(
                            habits: store.habits,
                            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                    }
                }
            })
    }
}
