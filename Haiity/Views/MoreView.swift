import Combine
import SwiftUI
import UniformTypeIdentifiers
import AuthenticationServices
import PhotosUI
import UIKit

/// Bildschirmartige Unterziele des Mehr-Bereichs — wertbasiert, damit
/// Deep-Links (haiity://stats, haiity://archive) direkt hinspringen können.
/// `Identifiable`, weil sie als `.sheet(item:)` präsentiert werden: in der
/// Tafel über der Leiste ist für eine eigene Seite kein Platz.
/// `developer` ist kein Deep-Link-Ziel und steht in keiner Liste: dorthin
/// führt nur die versteckte Tür in `AboutView` (sieben Tipps auf die
/// Versionszeile), und zwar als SCHUB im Blatt darüber — ein zweites Blatt
/// aus einem offenen Blatt heraus verschluckt iOS. Als Route zählt sie
/// trotzdem, damit `moreDestination` der EINE Ort bleibt, an dem steht,
/// welche Seite hinter welchem Ziel liegt.
enum MoreRoute: Hashable, Identifiable {
    case archive, about, developer, appearance, habitBehavior, timeZone, github

    var id: Self { self }
}

enum MoreScreen: Equatable {
    case main, appearance, habitBehavior, timeZone

    var title: String {
        switch self {
        case .main: String(localized: "Mehr")
        case .appearance: String(localized: "Darstellung")
        case .habitBehavior: String(localized: "Verhalten & Teilen")
        case .timeZone: String(localized: "Zeitzone")
        }
    }
}

/// "Mehr": iCloud-Status, Darstellung, Graph-Farbe, die beiden
/// Zusammenfassungen (Tag und Woche), Statistik, Archiv, Export/Import und
/// Über/Datenschutz.
///
/// Wohnt auf der MEHR-SEITE (fullScreenCover aus dem Menü oben rechts,
/// siehe ContentView.morePage) — wieder eine eigene Seite mit
/// System-Navigationsleiste. Die drei seitenartigen Ziele bleiben Knöpfe,
/// die ein Blatt öffnen (`onOpen`), präsentiert vom Aufrufer ÜBER der Seite.
///
struct MoreView: View {
    let store: HabitStore
    let github: GitHubContributionStore
    /// Nur Anzeige: es gibt nichts einzurichten. Entweder iCloud läuft, oder
    /// die Zeile sagt, warum nicht.
    let cloudStatus: CloudSyncStatus
    /// Synchronisierte Auswahl der Statistik-Karten.
    let statsCards: StatsCardStore
    /// Ein seitenartiges Ziel öffnen (Statistik, Archiv, Über).
    let onOpen: (MoreRoute) -> Void
    /// Zählt die eingetroffenen Deep-Links (siehe ContentView). Ein Link ist
    /// eine Absage an das, was gerade offen ist: der Tab wechselt unter dem
    /// Kaufblatt, und ohne dieses Signal bliebe der Nutzer auf einer
    /// Kaufseite sitzen, die zu einem Bereich gehört, den er verlassen hat.
    var routeToken: Int = 0
    var screen: MoreScreen = .main

    @State private var summaryDenied = false
    @State private var calendarDenied = false
    @State private var reminderSyncDenied = false
    @State private var weeklyDenied = false
    @State private var motivationDenied = false
    @State private var notificationDND = NotificationPromptPreference.state
    @State private var dndCustomDate = Date().addingTimeInterval(2 * 60 * 60)
    @State private var dndNow = Date()
    @State private var showReminderSetup = false
    @State private var pickedBackgroundItem: PhotosPickerItem?
    @State private var backgroundImageError = false
    @State private var backgroundImageImportToken = UUID()
    // App-Icon-Auswahl: was der Homescreen gerade zeigt, und ob der letzte
    // Wechsel scheiterte (supportsAlternateIcons == false o. ä.).
    @State private var currentIconName: String?
    @State private var iconChangeFailed = false
    @State private var aliasDraft = ""
    @State private var storedAppleName: String?
    @State private var storedAppleUserID: String?
    @State private var storedAppleEmail: String?
    @State private var appleSignInCameBackEmpty = false
    @State private var appleIdentityCopied = false
    @Environment(\.colorScheme) private var colorScheme
    /// Startwert = Petrol: bewusst KEINE der 18 Ankerfarben, damit die
    /// Vorschau sofort zeigt, dass frei gewählt und ehrlich gerundet wird.
    @State private var freeIconColor: Color = Theme.color(0x0F766E)
    // Eigene Farben: anlegen, bearbeiten, umbenennen, löschen.
    @State private var creatingPalette = false
    @State private var editingPalette: CustomPalette?
    @State private var renamingPalette: CustomPalette?
    @State private var renameText = ""
    @State private var deletingPalette: CustomPalette?
    /// Das Kaufblatt: `nil` heisst geschlossen. Der Kontext bestimmt nur die
    /// Kopfzeile — vier Zeilen dieser Seite können es öffnen.
    @State private var paywall: PaywallContext?
    /// Die Absicht, die das Kaufblatt unterbrochen hat — gesetzt NUR, wenn
    /// der Kauf wirklich vorliegt. Sie wird beim Zufahren des Blatts
    /// ausgeführt: bezahlen und dann vor demselben Schloss stehen ist der
    /// Moment, in dem sich ein Kauf wie ein Fehler anfühlt.
    @State private var purchased: PaywallContext?
    @State private var pendingCalendarItemType: HabitItemType = .habit
    @State private var pendingNativeReminder = false
    @State private var copiedSyncHint = false
    @State private var proStatus = ProStatus.shared
    @Environment(\.palettes) private var palettes

    private var currentAppearance: AppearancePreferences { store.appearancePreferences }
    private var hasPersistedBackgroundImage: Bool {
        currentAppearance.backgroundImageData != nil
    }

    /// Der eine Lesepunkt dieser Seite — und ein beobachtbarer (siehe
    /// `ProStatus`). Bewusst KEIN gespiegelter Zustand: der Kauf kann von
    /// einem anderen Blatt oder einem anderen Gerät kommen, und dann müssen
    /// die Schlösser hier trotzdem aufgehen.
    private var unlocked: Bool { proStatus.unlocked || Pro.isUnlocked }

    private var archivedCount: Int { store.habits.filter { $0.archivedAt != nil }.count }

    private var localCloudPreferences: CloudPreferences {
        CloudPreferences(calendarSyncHabits: CalendarSync.syncHabits,
                         calendarSyncReminders: CalendarSync.syncReminders,
                         nativeReminderSync: ReminderSync.isEnabled,
                         shakeToReportEnabled: ShakeToReport.isEnabled,
                         notificationDND: NotificationPromptPreference.state)
    }

    private func updateCloudPreferences(_ body: (inout CloudPreferences) -> Void) {
        store.updateCloudPreferences(fallback: localCloudPreferences, body)
    }

    var body: some View {
        #if DEBUG
        FrameProbe.shared.mark("MoreView.body")
        #endif
        return Group {
            switch screen {
            case .main: mainSettings
            case .appearance: appearanceSettings
            case .habitBehavior: habitBehaviorSettings
            case .timeZone: timeZoneSettings
            }
        }
        .navigationTitle(screen.title)
        .navigationBarTitleDisplayMode(.inline)
        // Farbe und Tint noch einmal: ein Blatt ist eine eigene Präsentation
        // und erbt die Umgebung des Bildschirms darunter nicht (siehe
        // ContentView).
        .sheet(isPresented: $creatingPalette) {
            CustomPaletteSheet(store: store).themed(store, palettes: palettes)
        }
        .onAppear {
            dndNow = .now
            notificationDND = store.cloudPreferences?.notificationDND
                ?? NotificationPromptPreference.state
            if notificationDND.mode == .custom, let until = notificationDND.until {
                dndCustomDate = until
            }
            #if DEBUG
            // Nur Debug: das Farb-Blatt direkt zeigen — Klicks durch die
            // Liste sind in der Sim-Automatisierung unzuverlässig.
            if ProcessInfo.processInfo.arguments.contains("-show-custom-palette") {
                creatingPalette = true
            }
            #endif
        }
        .task {
            while !Task.isCancelled {
                dndNow = .now
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(item: $editingPalette) { palette in
            CustomPaletteSheet(store: store, existing: palette)
                .themed(store, palettes: palettes)
        }
        .sheet(item: $paywall, onDismiss: resumeAfterPurchase) { context in
            PaywallView(context: context, store: store,
                        onUnlocked: { purchased = context })
                .themed(store, palettes: palettes)
        }
        // Ein Deep-Link gewinnt gegen jedes offene Kaufblatt: der Tab
        // wechselt darunter, also darf es nicht darüber liegen bleiben.
        .onChange(of: routeToken) { _, _ in
            purchased = nil
            paywall = nil
        }
        .onChange(of: store.appearancePreferences) { _, _ in
            // A force reset from the Developer page, or an iCloud merge, must
            // cancel a stale import before it can put the old image back.
            backgroundImageImportToken = UUID()
        }
        .fullScreenCover(isPresented: $showReminderSetup) {
            ReminderSetupView(isPresented: $showReminderSetup, store: store)
                .themed(store, palettes: palettes)
        }
        .alert(String(localized: "Farbe umbenennen"),
               isPresented: Binding(get: { renamingPalette != nil },
                                    set: { if !$0 { renamingPalette = nil } })) {
            TextField(String(localized: "Name"), text: $renameText)
                .accessibilityIdentifier("palette-rename-field")
            Button(String(localized: "Abbrechen"), role: .cancel) { renamingPalette = nil }
            Button(String(localized: "Sichern")) { commitRename() }
                .accessibilityIdentifier("palette-rename-save")
        }
        // Rückfrage NUR, wenn die Farbe wirklich benutzt wird — sonst wäre
        // sie eine Gebühr auf jeden Aufräumvorgang. Der Text sagt konkret,
        // was danach passiert, statt „Wirklich löschen?".
        .confirmationDialog(deleteQuestion,
                            isPresented: Binding(get: { deletingPalette != nil },
                                                 set: { if !$0 { deletingPalette = nil } }),
                            titleVisibility: .visible) {
            Button(String(localized: "Löschen"), role: .destructive) {
                if let id = deletingPalette?.id { store.removeCustomPalette(id) }
                deletingPalette = nil
            }
            .accessibilityIdentifier("palette-delete-confirm")
            Button(String(localized: "Abbrechen"), role: .cancel) { deletingPalette = nil }
        } message: {
            Text(String(localized: "Alles, was diese Farbe benutzt, fällt auf die Standardfarbe zurück."))
        }
        // Das App-Icon folgt der GLOBALEN Farbe — egal ob sie umgestellt oder
        // die aktive eigene Farbe umgefärbt wurde. Eine Stelle statt einer
        // Wiederholung an jedem Schreibvorgang.
        .onChange(of: store.palettes) { _, _ in
            guard store.matchAppIcon else { return }
            applyIconPreference()
        }
        .onChange(of: store.matchAppIcon) { _, _ in
            applyIconPreference()
        }
        .onChange(of: store.manualAppIconName) { _, _ in
            guard !store.matchAppIcon else { return }
            applyIconPreference()
        }
    }

    private var mainSettings: some View {
        List {
            proSection.settingsListRow()
            personalSection.settingsListRow()
            githubSection.settingsListRow()
            Section {
                pageRow(MoreRoute.appearance, title: String(localized: "Darstellung"),
                        symbol: "paintpalette", identifier: "open-appearance")
                pageRow(MoreRoute.habitBehavior, title: String(localized: "Verhalten & Teilen"),
                        symbol: "hand.draw", identifier: "open-habit-behavior")
            }
            .settingsListRow()
            notificationSettingsSection.settingsListRow()
            Section {
                pageRow(MoreRoute.archive, title: String(localized: "Archiv"),
                        symbol: "archivebox", identifier: "open-archive",
                        badge: archivedCount > 0 ? "\(archivedCount)" : nil)
            }
            .settingsListRow()
            Section {
                Button { showReminderSetup = true } label: {
                    Label(String(localized: "Setup wiederholen"), systemImage: "arrow.clockwise")
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("open-reminder-setup")
            }
            .settingsListRow()
            Section {
                pageRow(MoreRoute.about, title: String(localized: "Über & Datenschutz"),
                        symbol: "lock.shield", identifier: "open-about")
            }
            .settingsListRow()
        }
        .settingsSurface()
    }

    private var githubSection: some View {
        Section {
            HStack(spacing: Theme.Metrics.gap) {
                Button { onOpen(.github) } label: {
                    HStack(spacing: Theme.Metrics.gap) {
                        Label(String(localized: "GitHub"),
                              systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer(minLength: 0)
                        Text(github.snapshot?.username ?? String(localized: "Verbinden"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-github-settings")

                if github.snapshot != nil {
                    Button(String(localized: "Abmelden"), role: .destructive) {
                        github.disconnect()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("disconnect-github")
                }
            }
        }
    }

    private var appearanceSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                appearanceSection
                    .padding(Theme.Metrics.cardPadding)
                    .appSurface(cornerRadius: Theme.Metrics.cardRadius)
                paletteSection
                    .padding(Theme.Metrics.cardPadding)
                    .appSurface(cornerRadius: Theme.Metrics.cardRadius)
                compactModeSection
                    .padding(Theme.Metrics.cardPadding)
                    .appSurface(cornerRadius: Theme.Metrics.cardRadius)
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, Theme.Metrics.gap)
        }
        .scrollIndicators(.hidden)
        .settingsChrome()
    }

    private var habitBehaviorSettings: some View {
        List {
            timeZoneSection.settingsListRow()
            swipeActionsSection.settingsListRow()
            notificationActionsSection.settingsListRow()
            calendarSection.settingsListRow()
        }
        .settingsSurface()
    }

    private var timeZoneSection: some View {
        Section {
            pageRow(.timeZone,
                    title: String(localized: "Standardzeitzone"),
                    symbol: "globe",
                    identifier: "open-timezone",
                    badge: HabitTimeZone.displayName(for: store.defaultTimeZoneIdentifier))
        } footer: {
            Text(String(localized: "Neue Habits übernehmen diese Zeitzone. Einzelne Habits können sie überschreiben."))
        }
    }

    private var timeZoneSettings: some View {
        HabitTimeZoneList(selection: defaultTimeZoneBinding,
                          inheritedLabel: String(localized: "Gerätezeitzone"),
                          allowsDeviceOverride: false)
            .navigationTitle(String(localized: "Standardzeitzone"))
            .navigationBarTitleDisplayMode(.inline)
            .settingsSurface()
    }

    // Die Statistik-Karten-Auswahl stand hier (bis zu zwei Karten über der
    // Habit-Liste). Die Karten wohnen jetzt vollzählig im eigenen
    // Statistik-Tab — es gibt nichts mehr auszuwählen. `StatsCardPrefs`
    // bleibt als Datenformat bestehen (alte Dateien und iCloud-Stände
    // decodieren unverändert), nur die Oberfläche dazu ist weg.

    private var compactModeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Toggle(String(localized: "Kompakte Ansicht"), isOn: Binding(
                get: { statsCards.compactMode },
                set: { statsCards.compactMode = $0 }))
            .padding(.vertical, 2)
            .accessibilityIdentifier("compact-mode-toggle")
            Toggle(String(localized: "Rückgängig in Widgets"), isOn: Binding(
                get: { statsCards.widgetResetEnabled },
                set: { statsCards.widgetResetEnabled = $0 }))
            .padding(.vertical, 2)
            .accessibilityIdentifier("widget-reset-toggle")
        }
    }

    private var swipeActionsSection: some View {
        Section {
            Toggle(String(localized: "Wischaktionen"), isOn: Binding(
                get: { statsCards.preferences.swipeActions.enabled },
                set: { enabled in
                    statsCards.update { $0.swipeActions.enabled = enabled }
                }))
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
        } header: {
            Text(String(localized: "Wischaktionen"))
        }
    }

    private var notificationActionsSection: some View {
        Section {
            Toggle(String(localized: "Schnellaktionen in Mitteilungen"), isOn: Binding(
                get: { statsCards.preferences.notificationActionsEnabled },
                set: { enabled in
                    statsCards.update { $0.notificationActionsEnabled = enabled }
                    NotificationPresenter.configureQuickActions(
                        enabled: enabled,
                        choices: statsCards.preferences.notificationActions.slots)
                }))
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
        } header: {
            Text(String(localized: "Mitteilungen"))
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

    // Die Nacharbeiten-Einstellung (Malen/Auswählen) stand hier — der
    // Malen-Modus ist auf Nutzerwunsch entfernt, die Karte arbeitet immer
    // im Auswählen-Modus. Der alte App-Group-Schlüssel „backfillMode" wird
    // schlicht nicht mehr gelesen.

    // MARK: – hAiity Pro
    //
    // Steht direkt unter dem iCloud-Status und spricht dessen Sprache:
    // Symbolkachel, Titel, ein Satz. Und unmittelbar DARUNTER stehen die drei
    // Zeilen, die davon abhängen (Icon per Farbrad, eigene Farbe, Kalender) —
    // wer hier kauft, sieht das Ergebnis, ohne zu scrollen.
    //
    // Der Markenname bleibt unübersetzt (`verbatim`): er steht in keinem
    // Katalog und darf in keiner Sprache anders heissen.

    @ViewBuilder
    private var proSection: some View {
        Section {
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
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    private var proLock: some View {
        Image(systemName: "lock")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Nur mit hAiity Pro"))
    }

    // MARK: – Kalender
    //
    // Zwei Auswahlen: Habits und Erinnerungen mit Termin erscheinen in einem eigenen
    // hAiity-Kalender — und damit in Apple Kalender und (wenn das
    // Standardkonto ein Google-Konto ist) auch in Google Kalender. Der
    // Die Nutzerwahl reist über iCloud; Berechtigung, Kalenderkennung und
    // Termine bleiben gerätelokal und werden beim Abgleich geprüft.

    private var calendarSection: some View {
        Section {
            calendarToggle(type: .habit,
                           title: String(localized: "Habits im Kalender"),
                           identifier: "calendar-sync-habits-toggle")
            calendarToggle(type: .reminder,
                           title: String(localized: "Erinnerungen im Kalender"),
                           identifier: "calendar-sync-reminders-toggle")
            Toggle(isOn: reminderSyncBinding) {
                HStack {
                    Label(String(localized: "Erinnerungen mit Apple synchronisieren"),
                          systemImage: "checklist")
                    if !unlocked && !nativeReminderSyncEnabled {
                        Spacer(minLength: Theme.Metrics.gap)
                        proLock
                    }
                }
            }
            .accessibilityIdentifier("native-reminder-sync-toggle")
            syncWatermarkHints
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
    }

    private var syncWatermarkHints: some View {
        HStack(spacing: Theme.Metrics.gap) {
            Label(String(localized: "Kennzeichnung für eigene Einträge"),
                  systemImage: "tag")
            Spacer(minLength: Theme.Metrics.gap)
            Button {
                UIPasteboard.general.string = SyncWatermark.copyText
                copiedSyncHint = true
                Theme.Haptics.success()
            } label: {
                Label(copiedSyncHint ? String(localized: "Kopiert")
                                     : String(localized: "Kopieren"),
                      systemImage: copiedSyncHint ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("copy-sync-watermark")
        }
        .padding(.vertical, 4)
    }

    private func calendarToggle(type: HabitItemType,
                                title: String,
                                identifier: String) -> some View {
        Toggle(isOn: calendarBinding(for: type)) {
            HStack {
                Label(title, systemImage: type == .habit ? "calendar.badge.plus" : "bell.badge")
                let enabled = calendarEnabled(for: type)
                if !unlocked && !enabled {
                    Spacer(minLength: Theme.Metrics.gap)
                    proLock
                }
            }
        }
        .accessibilityIdentifier(identifier)
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

    // MARK: – Anrede
    //
    // Der Name macht Mitteilungen persönlich („Stark, Mo!") — mehr nicht.
    // Zwei Quellen: der Alias (geht IMMER, kein Konto nötig) und optional
    // der Vorname aus der Apple-Anmeldung; der Alias gewinnt. Apple liefert
    // den Namen nur bei der ERSTEN Anmeldung — schlägt das fehl oder kommt
    // leer zurück, sagt die Zeile das ehrlich, statt still nichts zu tun.

    private var personalSection: some View {
        Section {
            TextField(String(localized: "Alias"),
                      text: aliasBinding,
                      prompt: Text(String(localized: "Wie dürfen wir dich nennen?")))
                .textInputAutocapitalization(.words)
                .textContentType(.nickname)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .accessibilityIdentifier("personal-alias")
            if let storedAppleUserID {
                if let displayName = PersonalName.resolve(alias: aliasDraft,
                                                          appleName: storedAppleName) {
                    Label(String(format: String(localized: "Angemeldet als %@"), displayName),
                          systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    signOutFromApple()
                } label: {
                    Label(String(localized: "Abmelden"),
                          systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("apple-signout")
                if appleSignInCameBackEmpty && PersonalName.effective == nil {
                    Text(String(localized: "Apple hat keinen Namen geliefert. Nutze einen Alias."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !DeveloperAccess.isOwnerDevice(storedAppleUserID: storedAppleUserID,
                                                  storedAppleEmail: storedAppleEmail) {
                    Button {
                        UIPasteboard.general.string = storedAppleUserID
                        appleIdentityCopied = true
                        Theme.Haptics.success()
                    } label: {
                        Label(String(localized: appleIdentityCopied ? "Kennung kopiert." : "Kennung kopieren"),
                              systemImage: appleIdentityCopied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityIdentifier("copy-unrecognized-apple-user-id")
                }
            } else {
                appleSignInButton
                if appleSignInCameBackEmpty {
                    Text(String(localized: "Apple hat keinen Namen geliefert. Nutze einen Alias."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(String(localized: "Anrede"))
        }
        .onAppear {
            aliasDraft = PersonalName.alias ?? ""
            storedAppleName = PersonalName.appleName
            storedAppleUserID = PersonalName.appleUserID
            storedAppleEmail = PersonalName.appleEmail
        }
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 40)
        .accessibilityIdentifier("apple-signin")
    }

    private var aliasBinding: Binding<String> {
        Binding(get: { aliasDraft },
                set: { value in
                    aliasDraft = value
                    PersonalName.alias = value
                })
    }

    private func signOutFromApple() {
        PersonalName.appleName = nil
        PersonalName.appleUserID = nil
        PersonalName.appleEmail = nil
        storedAppleName = nil
        storedAppleUserID = nil
        storedAppleEmail = nil
        appleSignInCameBackEmpty = false
        appleIdentityCopied = false
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
            // Abbruch/Fehler: kein Banner, keine Strafe — der Alias bleibt
            // der immer offene Weg.
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let credentialName = credential.fullName?.givenName
            ?? credential.fullName.map { formatter.string(from: $0) }
        // Die undurchsichtige Kennung IMMER mitnehmen — auch wenn Apple
        // keinen Vornamen liefert (das tut es nur bei der allerersten
        // Anmeldung). Sie ist der einzige Weg, dieses Gerät später als das
        // des Besitzers zu erkennen (siehe `DeveloperAccess.isOwnerDevice`),
        // und sie hängt nicht daran, ob ein Name dabei war.
        let existingUserID = PersonalName.appleUserID
        let resolvedName = AppleSignInIdentity.resolvedName(
            credentialName: credentialName,
            existingName: PersonalName.appleName,
            existingUserID: existingUserID,
            userID: credential.user)
        let resolvedEmail = AppleSignInIdentity.resolvedEmail(
            credentialEmail: credential.email,
            identityToken: credential.identityToken,
            existingEmail: PersonalName.appleEmail,
            existingUserID: existingUserID,
            userID: credential.user,
            audience: Bundle.main.bundleIdentifier ?? "com.aiity.haiity")
        PersonalName.appleUserID = credential.user
        PersonalName.appleEmail = resolvedEmail
        storedAppleUserID = PersonalName.appleUserID
        storedAppleEmail = PersonalName.appleEmail
        let aliasEmail = resolvedEmail ?? (DeveloperAccess.isOwnerDevice(
            storedAppleUserID: credential.user,
            storedAppleEmail: nil) ? DeveloperAccess.ownerAppleEmail : nil)
        let suggestedAlias = AppleSignInIdentity.suggestedAlias(
            resolvedName: resolvedName,
            email: aliasEmail)
        if let resolvedName {
            PersonalName.appleName = resolvedName
            storedAppleName = PersonalName.appleName
        }
        if PersonalName.alias == nil, let suggestedAlias {
            PersonalName.alias = suggestedAlias
            aliasDraft = suggestedAlias
        }
        appleSignInCameBackEmpty = PersonalName.effective == nil
        // Apple sign-in is an account boundary. Re-read the entitlement with
        // downgrade permission so a previous account cannot keep paid gates
        // open after this account is signed in.
        Task { await Pro.refresh(mayDowngrade: true) }
        Theme.Haptics.success()
    }

    private func calendarBinding(for type: HabitItemType) -> Binding<Bool> {
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
                        CalendarSync.reconcile(
                            habits: store.habits,
                            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
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
                        CalendarSync.reconcile(
                            habits: store.habits,
                            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                    }
                }
            })
    }

    private var reminderSyncBinding: Binding<Bool> {
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
                        await MainActor.run {
                            reminderSyncDenied = !granted
                            guard granted else { return }
                            ReminderSync.isEnabled = true
                            updateCloudPreferences { $0.nativeReminderSync = true }
                            ReminderSync.startObserving(store: store)
                            ReminderSync.reconcile(
                                habits: store.habits,
                                defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                        }
                    }
                }
            })
    }

    // MARK: – Darstellung
    //
    // Erscheinungsbild und Graph-Farbe stehen bewusst in EINEM Abschnitt und
    // trotzdem als zwei getrennte Einstellungen: beides beantwortet „wie
    // sieht die App aus", aber niemand will Hell/Dunkel mitverstellen, nur
    // weil er das Grün loswerden möchte.

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap + 2) {
            Text(String(localized: "Darstellung"))
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.Metrics.gap) {
                Label(String(localized: "Erscheinungsbild"), systemImage: "circle.lefthalf.filled")
                Spacer(minLength: Theme.Metrics.gap)
                Menu {
                    ForEach(AppearanceSetting.allCases, id: \.self) { option in
                        Button {
                            appearanceBinding.wrappedValue = option
                        } label: {
                            HStack {
                                Text(option.displayName)
                                Spacer()
                                if option == store.appearance {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(store.appearance.displayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.tint)
                }
                .accessibilityIdentifier("appearance-picker")
            }

            // Vorschau statt Wortliste: jede Oberfläche als Miniaturfläche
            // in DEM Material, das sie später wirklich hat (siehe
            // MaterialPreviewPicker). Ein segmentiertes Steuerelement trug
            // vier Begriffe ohne jeden Anhaltspunkt, wie sie aussehen.
            MaterialPreviewPicker(selection: materialBinding)
                .accessibilityIdentifier("appearance-material-picker")

            backgroundControl

            Toggle(isOn: matchIconBinding) {
                HStack(alignment: .center, spacing: Theme.Metrics.gap) {
                    Image(systemName: "app.badge")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "App-Icon dynamisch"))
                        Text(String(localized: "Gleiche Farbe wie Graph-Farbe."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("match-icon-toggle")

            if !store.matchAppIcon {
                iconGrid
            }

            if iconChangeFailed {
                Text(String(localized: "Der Icon-Wechsel ist auf diesem Gerät gerade nicht möglich."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var materialBinding: Binding<AppearanceMaterial> {
        Binding(
            get: { store.appearancePreferences.material },
            set: { material in
                updateAppearance { $0.material = material }
            })
    }

    private var backgroundModeBinding: Binding<AppearanceBackgroundMode> {
        Binding(
            get: { store.appearancePreferences.backgroundMode },
            set: { mode in
                backgroundImageImportToken = UUID()
                updateAppearance {
                    $0.selectBackgroundMode(mode)
                }
                pickedBackgroundItem = nil
            })
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Theme.color(store.appearancePreferences.backgroundColorHex
                            ?? fallbackBackgroundColorHex)
            },
            set: { color in
                updateAppearance { $0.backgroundColorHex = Theme.hex(from: color) }
            })
    }

    private var gradientStartBinding: Binding<Color> {
        Binding(
            get: {
                Theme.color(store.appearancePreferences.gradientStartHex
                            ?? fallbackGradientStartHex)
            },
            set: { color in
                updateAppearance { $0.gradientStartHex = Theme.hex(from: color) }
            })
    }

    private var gradientEndBinding: Binding<Color> {
        Binding(
            get: {
                Theme.color(store.appearancePreferences.gradientEndHex
                            ?? fallbackGradientEndHex)
            },
            set: { color in
                updateAppearance { $0.gradientEndHex = Theme.hex(from: color) }
            })
    }

    private var fallbackBackgroundColorHex: UInt32 {
        colorScheme == .dark ? 0x1C1C1E : 0xF2F2F7
    }

    private var fallbackGradientStartHex: UInt32 {
        colorScheme == .dark ? 0x1C1C1E : 0xF2F2F7
    }

    private var fallbackGradientEndHex: UInt32 {
        colorScheme == .dark ? 0x2C2C2E : 0xE5E5EA
    }

    /// A small set of calm starting points keeps the background editor useful
    /// without turning it into a wall of color controls. The ColorPicker still
    /// accepts any custom color.
    private static let backgroundSwatches: [UInt32] = [
        0xF4F7F2, 0xE7F0FA, 0xF7ECE2, 0xF0EAF7,
        0x202428, 0x202B2A, 0x24263A, 0x2D2520
    ]

    private func updateAppearance(_ body: (inout AppearancePreferences) -> Void) {
        var next = store.appearancePreferences
        body(&next)
        store.appearancePreferences = next
    }

    private var backgroundControl: some View {
        return VStack(alignment: .leading, spacing: Theme.Metrics.gap + 2) {
            Text(String(localized: "Hintergrund"))
                .font(.subheadline.weight(.semibold))

            backgroundPreview

            backgroundModeSelector

            switch store.appearancePreferences.backgroundMode {
            case .color:
                backgroundColorRow(title: String(localized: "Farbe"),
                                   symbol: "circle.fill",
                                   selection: backgroundColorBinding,
                                   selectedHex: store.appearancePreferences.backgroundColorHex) { hex in
                    updateAppearance { $0.backgroundColorHex = hex }
                }
                .accessibilityIdentifier("appearance-background-color-picker")
            case .gradient:
                backgroundColorRow(title: String(localized: "Oben"),
                                   symbol: "arrow.up",
                                   selection: gradientStartBinding,
                                   selectedHex: store.appearancePreferences.gradientStartHex) { hex in
                    updateAppearance { $0.gradientStartHex = hex }
                }
                    .accessibilityIdentifier("appearance-gradient-start-picker")
                backgroundColorRow(title: String(localized: "Unten"),
                                   symbol: "arrow.down",
                                   selection: gradientEndBinding,
                                   selectedHex: store.appearancePreferences.gradientEndHex) { hex in
                    updateAppearance { $0.gradientEndHex = hex }
                }
                    .accessibilityIdentifier("appearance-gradient-end-picker")
            case .image:
                backgroundImagePicker
            }
        }
    }

    private var backgroundModeSelector: some View {
        Picker(selection: backgroundModeBinding) {
            ForEach(AppearanceBackgroundMode.allCases, id: \.self) { mode in
                Label(mode.displayName, systemImage: backgroundSymbol(for: mode))
                    .tag(mode)
            }
        } label: {
            Text(String(localized: "Hintergrund"))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("appearance-background-mode-picker")
    }

    private func backgroundSymbol(for mode: AppearanceBackgroundMode) -> String {
        switch mode {
        case .color: "circle.fill"
        case .gradient: "circle.lefthalf.filled"
        case .image: "photo"
        }
    }

    private func backgroundColorRow(title: String,
                                    symbol: String,
                                    selection: Binding<Color>,
                                    selectedHex: UInt32?,
                                    apply: @escaping (UInt32) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            HStack(spacing: Theme.Metrics.gap) {
                Label(title, systemImage: symbol)
                    .foregroundStyle(.primary)
                Spacer(minLength: Theme.Metrics.gap)
                ColorPicker(String(localized: "Eigene Farbe"),
                            selection: selection,
                            supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityIdentifier("appearance-custom-color-\(title)")
            }
            HStack(spacing: 10) {
                ForEach(Self.backgroundSwatches, id: \.self) { hex in
                    Button {
                        apply(hex)
                    } label: {
                        Circle()
                            .fill(Theme.color(hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle()
                                    .stroke(hex == selectedHex
                                            ? Color.primary.opacity(0.85)
                                            : Color.primary.opacity(0.16),
                                            lineWidth: hex == selectedHex ? 2 : 0.75)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Farbton"))
                }
            }
        }
    }

    @ViewBuilder
    private var backgroundPreview: some View {
        ZStack(alignment: .bottomLeading) {
            switch store.appearancePreferences.backgroundMode {
            case .color:
                Theme.color(store.appearancePreferences.backgroundColorHex
                            ?? fallbackBackgroundColorHex)
            case .gradient:
                LinearGradient(
                    colors: [
                        Theme.color(store.appearancePreferences.gradientStartHex
                                    ?? fallbackGradientStartHex),
                        Theme.color(store.appearancePreferences.gradientEndHex
                                    ?? fallbackGradientEndHex)
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            case .image:
                AppearanceCachedImage(data: currentAppearance.imagePayload) {
                    Color(.systemGroupedBackground)
                }
            }
            Color(.systemBackground).opacity(colorScheme == .dark ? 0.18 : 0.08)
            HStack(spacing: 6) {
                Text(verbatim: "hAiity")
                    .font(.headline.weight(.bold))
                Text(String(localized: "dein Raum"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var backgroundImagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Metrics.gap) {
                PhotosPicker(selection: $pickedBackgroundItem,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Label(String(localized: "Bild auswählen"),
                          systemImage: "photo.on.rectangle.angled")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("appearance-background-picker")

                if hasPersistedBackgroundImage {
                    Button(role: .destructive) {
                        backgroundImageImportToken = UUID()
                        pickedBackgroundItem = nil
                        store.removeBackgroundImage()
                        backgroundImageError = false
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Circle())
                    .help(String(localized: "Hintergrundbild entfernen"))
                    .accessibilityLabel(String(localized: "Hintergrundbild entfernen"))
                    .accessibilityIdentifier("appearance-background-remove")
                }
            }
            .onChange(of: pickedBackgroundItem) { _, item in
                guard let item else { return }
                backgroundImageError = false
                let token = UUID()
                backgroundImageImportToken = token
                Task {
                    do {
                        let data = try await item.loadTransferable(type: Data.self)
                        await MainActor.run {
                            guard token == backgroundImageImportToken else { return }
                            guard let data else {
                                backgroundImageError = true
                                pickedBackgroundItem = nil
                                return
                            }
                            importBackgroundImage(data)
                            pickedBackgroundItem = nil
                        }
                    } catch {
                        await MainActor.run {
                            guard token == backgroundImageImportToken else { return }
                            backgroundImageError = true
                            pickedBackgroundItem = nil
                        }
                    }
                }
            }

            if currentAppearance.imagePayload != nil {
                AppearanceCachedImage(data: currentAppearance.imagePayload) {
                    Color(.secondarySystemGroupedBackground)
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel(String(localized: "Ausgewähltes Hintergrundbild"))
            }
            if backgroundImageError {
                Text(String(localized: "Das Bild konnte nicht übernommen werden."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func importBackgroundImage(_ data: Data) {
        let token = UUID()
        backgroundImageImportToken = token
        Task {
            let normalized = await Task.detached(priority: .userInitiated) {
                AppearanceImage.normalizedData(data)
            }.value
            await MainActor.run {
                guard token == backgroundImageImportToken else { return }
                guard let normalized else {
                    backgroundImageError = true
                    return
                }
                var next = store.appearancePreferences
                guard next.setBackgroundImage(normalized) else {
                    backgroundImageError = true
                    return
                }
                store.appearancePreferences = next
                backgroundImageError = false
            }
        }
    }

    // MARK: – App-Icon-Auswahl
    //
    // Der Schalter darüber ist der AUTOMATIK-Modus (Icon folgt der
    // Graph-Farbe). Das Raster ist der manuelle: ein Tipp setzt das Icon fest
    // und schaltet die Automatik aus. Vorher gab es NUR den Schalter — und
    // wer die grüne Standardfarbe benutzt, sah beim Umlegen exakt nichts
    // (Grün ist das Primär-Icon), was sich als „deaktiviert" las.

    private var iconGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                ForEach(GraphPalette.allCases) { palette in
                    iconCell(named: AppIcons.name(for: palette),
                             style: palette.style,
                             label: palette.displayName,
                             identifier: "app-icon-\(palette.rawValue)")
                }
                ForEach(AppIcons.hues) { hue in
                    iconCell(named: hue.name,
                             style: hue.style,
                             label: String(localized: "Farbton \(hue.degrees)°"),
                             identifier: "app-icon-h\(hue.degrees)")
                }
            }
            freeIconColorRow
        }
        .padding(.vertical, 4)
        .onAppear {
            currentIconName = AppIcons.validManualName(store.manualAppIconName)
                ?? UIApplication.shared.alternateIconName
        }
    }

    /// Welches Icon gerade auf dem Homescreen liegt — mit Automatik das aus
    /// der Graph-Farbe hergeleitete, sonst das zuletzt gesetzte.
    private var selectedIconName: String? {
        store.matchAppIcon
            ? AppIcons.iconName(for: palettes.global, customs: palettes.customs)
            : currentIconName
    }

    private func iconCell(named name: String?, style: PaletteStyle,
                          label: String, identifier: String) -> some View {
        let selected = selectedIconName == name
        return Button {
            chooseIcon(named: name)
        } label: {
            VStack(spacing: 4) {
                // Gezeichnet statt aus dem Katalog geladen: die
                // Alternate-Iconsets liegen in Assets.car, aber
                // `UIImage(named:)` findet .appiconset-Bilder nicht
                // zuverlässig (im Simulator gar nicht). Die Miniatur baut
                // das Icon-Motiv nach — dunkle Kachel, Raster in der Rampe.
                iconThumbnail(style: style)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(selected ? Theme.accentFill(palettes.style)
                                                   : Color.secondary.opacity(0.25),
                                          lineWidth: selected ? 2.5 : 1))
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(selected
                                     ? AnyShapeStyle(Theme.accentText(palettes.style))
                                     : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// Freie Farbe: das Farbrad wählt, die Miniatur daneben zeigt EHRLICH
    /// das eingebaute Icon, das daraus wird (iOS kann nur mitgelieferte
    /// Icons setzen), und „Anwenden" setzt genau dieses.
    private var freeIconColorRow: some View {
        HStack(spacing: 12) {
            ColorPicker(selection: $freeIconColor, supportsOpacity: false) {
                Label(String(localized: "Eigene Icon-Farbe"), systemImage: "paintpalette")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("icon-color-picker")
            .frame(maxWidth: .infinity)
            iconThumbnail(style: AppIcons.style(forIconName: snappedFreeIconName))
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            freeIconColorAction
        }
    }

    /// Gegated ist nur das SETZEN. Farbrad und ehrliche Vorschau bleiben —
    /// wer sehen will, welches der 18 Icons aus seiner Farbe würde, soll das
    /// sehen dürfen; die 18 Kacheln darüber sind ohnehin frei.
    @ViewBuilder
    private var freeIconColorAction: some View {
        if unlocked {
            Button(String(localized: "Anwenden")) {
                chooseIcon(named: snappedFreeIconName)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Theme.accentFill(palettes.style))
            .accessibilityIdentifier("icon-color-apply")
        } else {
            Button {
                paywall = .icon
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "lock")
                    Text(verbatim: "Pro")
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Nur mit hAiity Pro"))
            .accessibilityIdentifier("icon-color-pro")
        }
    }

    private var snappedFreeIconName: String? {
        AppIcons.iconName(forBase: Theme.hex(from: freeIconColor))
    }

    /// Das Icon-Motiv als Miniatur: dunkle Kachel, darauf ein 2×2-Raster in
    /// den Stufen der Familie — dieselbe Rampe wie im Jahresraster.
    private func iconThumbnail(style: PaletteStyle) -> some View {
        ZStack {
            Color(red: 0.09, green: 0.11, blue: 0.10)
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { col in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.level([2, 4, 3, 1][row * 2 + col],
                                                  dark: true, palette: style))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }

    /// Manuelle Wahl: Automatik aus, Icon setzen, Ergebnis zurückmelden.
    private func chooseIcon(named name: String?) {
        store.manualAppIconName = name
        store.matchAppIcon = false
        Task {
            let ok = await AppIcons.set(name)
            await MainActor.run {
                iconChangeFailed = !ok
                // Nicht zurücklesen: `alternateIconName` hinkt der Animation
                // des System-Dialogs hinterher, und die Markierung stünde
                // einen Moment auf dem falschen Icon.
                currentIconName = ok ? name
                                     : UIApplication.shared.alternateIconName
            }
        }
    }

    // MARK: – Graph-Farbe
    //
    // Die Auswahl IST das Raster: jede Zeile zeigt ihre fünf Stufen als
    // dieselben Quadrate, die später im Jahresraster stehen (`GridCell`),
    // nicht als Farbpunkte. Eine eigene Farbe steht gleichberechtigt zwischen
    // den eingebauten — sie kann nur zusätzlich umbenannt, umgefärbt und
    // gelöscht werden.

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Graph-Farbe"))
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, Theme.Metrics.gap)

            ForEach(GraphPalette.allCases) { palette in
                PaletteRow(style: palette.style,
                           title: palette.displayName,
                           selected: store.palette == .builtin(palette)) {
                    select(.builtin(palette))
                }
                .accessibilityIdentifier("palette-row-\(palette.rawValue)")
                .padding(.vertical, Theme.Metrics.gap)
            }
            ForEach(unlocked ? store.customPalettes : []) { custom in
                PaletteRow(style: custom.style,
                           title: custom.displayName,
                           selected: store.palette == .custom(custom.id)) {
                    selectCustomPalette(custom.id)
                }
                .accessibilityIdentifier("palette-row-custom-\(custom.id.uuidString)")
                .padding(.vertical, Theme.Metrics.gap)
                .swipeActions(edge: .trailing) {
                    // Rot EXPLIZIT: der App-Tint (die eigene Farbe!) würde die
                    // zerstörende Rolle sonst übermalen — eine Löschen-Taste in
                    // Petrol sieht aus wie eine harmlose Aktion.
                    Button(role: .destructive) { requestDelete(custom) } label: {
                        Label(String(localized: "Löschen"), systemImage: "trash")
                    }
                    .tint(.red)
                    Button { editingPalette = custom } label: {
                        Label(String(localized: "Bearbeiten"), systemImage: "paintpalette")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        renameText = custom.name
                        renamingPalette = custom
                    } label: {
                        Label(String(localized: "Umbenennen"), systemImage: "pencil")
                    }
                    Button { editingPalette = custom } label: {
                        Label(String(localized: "Bearbeiten"), systemImage: "paintpalette")
                    }
                    Button(role: .destructive) { requestDelete(custom) } label: {
                        Label(String(localized: "Löschen"), systemImage: "trash")
                    }
                }
            }
            Button {
                requestCustomPalette()
            } label: {
                HStack {
                    Label(String(localized: "Eigene Farbe …"), systemImage: "plus.circle")
                    if !unlocked {
                        Spacer(minLength: Theme.Metrics.gap)
                        proLock
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .padding(.vertical, Theme.Metrics.gap)
            .accessibilityIdentifier("palette-add-custom")
        }
    }

    /// Frage im Löschen-Dialog. Sie NENNT, was betroffen ist — eine Farbe,
    /// die gerade nichts einfärbt, wird ohne Rückfrage gelöscht.
    private var deleteQuestion: String {
        guard let palette = deletingPalette else { return "" }
        return String(localized: "„\(palette.displayName)“ wird noch benutzt. Löschen?")
    }

    /// Eigene Farben ANLEGEN ist Pro — der Bestand nicht: vorhandene eigene
    /// Farben bleiben wählbar, umbenennbar, bearbeitbar und löschbar. Bezahlt
    /// wird das Neue, nie das Vorhandene.
    private func requestCustomPalette() {
        guard ProGate.mayUseProFeature(unlocked: unlocked) else {
            paywall = .palette
            return
        }
        creatingPalette = true
    }

    private func selectCustomPalette(_ id: UUID) {
        guard ProGate.mayUseProFeature(unlocked: unlocked) else {
            paywall = .palette
            return
        }
        select(.custom(id))
    }

    /// Was nach einem erfolgreichen Kauf weiterläuft. Erst beim ZUFAHREN des
    /// Blatts: eine zweite Präsentation, die im Abgang der ersten startet,
    /// schluckt iOS.
    ///
    /// `.settings` steht bewusst nicht hier — diese Zeile hat nichts
    /// unterbrochen, die Seite zeigt den Kauf jetzt einfach als
    /// freigeschaltet. `.habits` und `.stats` gehören anderen Bildschirmen.
    private func resumeAfterPurchase() {
        guard let intent = purchased else { return }
        purchased = nil
        switch intent {
        case .calendar:
            if pendingNativeReminder {
                pendingNativeReminder = false
                reminderSyncBinding.wrappedValue = true
            } else {
                // Über die Bindung, nicht daran vorbei: sie ist der EINE Weg,
                // der das Gate prüft und danach den Kalender-Zugriff erfragt.
                calendarBinding(for: pendingCalendarItemType).wrappedValue = true
            }
        case .palette:
            creatingPalette = true
        case .icon:
            chooseIcon(named: snappedFreeIconName)
        case .habits, .stats, .settings:
            break
        }
    }

    private func requestDelete(_ palette: CustomPalette) {
        if store.isCustomPaletteInUse(palette.id) {
            deletingPalette = palette
        } else {
            store.removeCustomPalette(palette.id)
        }
    }

    private func commitRename() {
        guard var palette = renamingPalette else { return }
        palette.name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateCustomPalette(palette)
        renamingPalette = nil
    }

    /// Global gibt es kein „Wie App": eine Farbe ist immer gesetzt.
    private func select(_ ref: PaletteRef) {
        guard ref != store.palette else { return }
        store.palette = ref
    }

    // MARK: – Seitenartige Ziele
    //
    // Statistik, Archiv und Über sind SEITEN und werden als Blatt geöffnet.
    // Sie sehen aus wie ein `NavigationLink` (Chevron rechts), weil sie sich
    // genauso anfühlen sollen — nur dass sie nicht in einen Stapel schieben,
    // den die Tafel gar nicht hat.
    //
    // Hier stand einmal der Abschnitt „Wischgesten" mit zwei Pickern. Die
    // Gesten selbst sind weg (lange drücken statt wischen, siehe HabitCard),
    // und damit auch die Einstellung: eine sichtbare Aktionsliste muss
    // niemand einstellen.

    private func pageRow(_ route: MoreRoute,
                         title: String,
                         symbol: String,
                         identifier: String,
                         badge: String? = nil) -> some View {
        Button {
            onOpen(route)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier(identifier)
    }

    private var appearanceBinding: Binding<AppearanceSetting> {
        Binding(get: { store.appearance }, set: { store.appearance = $0 })
    }

    private var defaultTimeZoneBinding: Binding<String?> {
        Binding(get: { store.defaultTimeZoneIdentifier },
                set: { store.defaultTimeZoneIdentifier = $0 })
    }

    private var matchIconBinding: Binding<Bool> {
        Binding(
            get: { store.matchAppIcon },
            set: { on in
                store.matchAppIcon = on
                applyIconPreference()
            })
    }

    private func applyIconPreference() {
        let wanted = store.matchAppIcon
            ? AppIcons.iconName(for: palettes.global, customs: palettes.customs)
            : AppIcons.validManualName(store.manualAppIconName)
        Task {
            let ok = await AppIcons.set(wanted)
            await MainActor.run {
                currentIconName = ok ? wanted : UIApplication.shared.alternateIconName
            }
        }
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

    private var notificationSettingsSection: some View {
        Section {
            // One notification block keeps the related controls together;
            // spacing separates the groups without the cramped divider stack.
            VStack(alignment: .leading, spacing: Theme.Metrics.gutter + 6) {
                notificationOptOutRows
                dailySummaryRows
                weeklySummaryRows
                motivationRows
            }
            .padding(.vertical, Theme.Metrics.gap)
        } header: {
            Text(String(localized: "Mitteilungen"))
        }
    }

    private var notificationOptOutRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: dndEnabled) {
                Label(NotificationDNDPresentation.title,
                      systemImage: NotificationDNDPresentation.symbolName)
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
                if notificationDND.mode == .custom {
                    DatePicker(String(localized: "Bis"), selection: dndCustomDateBinding,
                               in: Date().addingTimeInterval(60)...)
                        .accessibilityIdentifier("dnd-custom-date")
                }
                Text(dndEndText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
    }

    private var dailySummaryRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: dailyEnabled) {
                Label(String(localized: "Tageszusammenfassung"), systemImage: "sun.max")
            }
            .disabled(dndActive)
            .accessibilityIdentifier("summary-toggle")
            if store.summaryMinutes != nil {
                DatePicker(String(localized: "Uhrzeit"),
                           selection: dailyTime,
                           displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("summary-time")
            }
            if summaryDenied { permissionHint }
        }
    }

    private var weeklySummaryRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: weeklyEnabled) {
                Label(String(localized: "Wochenzusammenfassung"), systemImage: "calendar")
            }
            .disabled(dndActive)
            .accessibilityIdentifier("weekly-summary-toggle")
            if store.weeklySummaryMinutes != nil {
                Picker(String(localized: "Wochentag"), selection: weeklyWeekday) {
                    ForEach(orderedWeekdays, id: \.self) { day in
                        Text(RecurrenceText.weekdayName(day)).tag(day)
                    }
                }
                .accessibilityIdentifier("weekly-summary-weekday")
                DatePicker(String(localized: "Uhrzeit"),
                           selection: weeklyTime,
                           displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("weekly-summary-time")
            }
            if weeklyDenied { permissionHint }
        }
    }

    private var motivationRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: motivationEnabled) {
                Label(String(localized: "Tägliche Motivation"), systemImage: "quote.bubble")
            }
            .disabled(dndActive)
            .accessibilityIdentifier("motivation-toggle")
            if store.motivationMinutes != nil {
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
            }
            if motivationDenied { permissionHint }
        }
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

/// Export als teilbare JSON-Datei — die Daten entstehen erst beim Teilen.
struct HabitExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("haiity-export.json")
    }
}

/// Kurz und ehrlich: das Kein-Server-Prinzip — und ganz unten die
/// Versionszeile, hinter der die versteckte Tür zum Entwicklerbereich sitzt.
struct AboutView: View {
    let store: HabitStore
    /// Bereits getätigte Tipps auf die Versionszeile. Bewusst NICHT
    /// gespeichert: eine halb geöffnete Tür soll den Bildschirm nicht
    /// überleben (siehe `DeveloperAccess`).
    @State private var taps = 0
    /// Refreshed on appearance because Sign in with Apple may establish the
    /// owner identity while More is already alive below this page.
    @State private var developerAvailable = false
    @State private var shakeToReport = ShakeToReport.isEnabled

    var body: some View {
        List {
            Section(String(localized: "Über hAiity")) {
                Text(String(localized: "Dein Alltag als Contribution-Graph."))
                    .font(.subheadline)
            }
            .settingsListRow()
            Section(String(localized: "Datenschutz")) {
                Text(String(localized: "Kein Tracking, kein hAiity-Server. Deine Daten bleiben auf deinen Geräten und in deiner privaten iCloud."))
                    .font(.subheadline)
            }
            .settingsListRow()
            Section {
                Toggle(String(localized: "Schütteln zum Melden"), isOn: Binding(
                    get: { shakeToReport },
                    set: { enabled in
                        shakeToReport = enabled
                        ShakeToReport.isEnabled = enabled
                        store.updateCloudPreferences(
                            fallback: CloudPreferences(
                                calendarSyncHabits: CalendarSync.syncHabits,
                                calendarSyncReminders: CalendarSync.syncReminders,
                                nativeReminderSync: ReminderSync.isEnabled,
                                shakeToReportEnabled: ShakeToReport.isEnabled,
                                notificationDND: NotificationPromptPreference.state)) {
                            $0.shakeToReportEnabled = enabled
                        }
                    }))
                    .accessibilityIdentifier("shake-to-report-toggle")
            }
            .settingsListRow()
            Section {
                versionRow
                if developerAvailable { developerRow }
            }
            .settingsListRow()
        }
        .settingsSurface()
        .navigationTitle(String(localized: "Über"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            shakeToReport = store.cloudPreferences?.shakeToReportEnabled ?? ShakeToReport.isEnabled
            developerAvailable = DeveloperAccess.isAvailable(
                storedAppleUserID: PersonalName.appleUserID,
                storedAppleEmail: PersonalName.appleEmail)
        }
        .onReceive(NotificationCenter.default.publisher(for: ShakeToReport.didChange)) { _ in
            shakeToReport = ShakeToReport.isEnabled
        }
    }

    /// Die Tür. Sie sieht aus wie eine Fußzeile und ist eine: die Version
    /// gehört ohnehin in jede Meldung. Erst ab dem vierten Tipp verrät der
    /// Countdown, dass da etwas ist — vorher wäre sie keine versteckte Tür.
    private var versionRow: some View {
        Button {
            tapVersion()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AppBuildInfo.versionLine)
                if let hint = DeveloperAccess.hint(for: taps) {
                    Text(hint)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-version")
    }

    private var developerRow: some View {
        NavigationLink(value: MoreRoute.developer) {
            Label(String(localized: "Entwickler"), systemImage: "hammer")
        }
        .accessibilityIdentifier("open-developer")
    }

    /// Ein Tipp weiter. Gerechnet wird in `DeveloperAccess`; hier steht nur,
    /// was die ANSICHT damit tut — den einen Schreibvorgang und den Stups,
    /// der das Aufgehen der Tür spürbar macht.
    ///
    /// **Auf fremden Geräten passiert NICHTS.** Kein Countdown, keine
    /// Zählung, kein Stups — die Zeile bleibt eine Versionszeile. Eine Tür,
    /// die sich einen Spalt bewegt, verrät, dass sie eine ist; und der
    /// Countdown „Noch 3 Tipps …" wäre die Anleitung gleich dazu. Wem die Tür
    /// gehört, entscheidet `DeveloperAccess.isOwnerDevice`.
    private func tapVersion() {
        guard DeveloperAccess.isOwnerDevice(storedAppleUserID: PersonalName.appleUserID,
                                                  storedAppleEmail: PersonalName.appleEmail) else {
            return
        }
        let step = DeveloperAccess.next(taps: taps)
        taps = step.taps
        guard step.unlocked else { return }
        DeveloperAccess.isUnlocked = true
        // Ohne Nachfrage: Der Riegel oben hat gerade bestätigt, dass dieses
        // Gerät dem Besitzer gehört — ein zweiter Aufruf derselben Regel im
        // selben Atemzug wäre nur eine Wiederholung.
        developerAvailable = true
        Theme.Haptics.success()
    }
}
