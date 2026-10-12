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
    case settings, archive, about, developer, appearance, habitBehavior, github, localModel, dataTransfer, calendar, notifications, personalization

    var id: Self { self }
}

enum MoreScreen: Hashable {
    case main, appearance, habitBehavior, localModel, calendar, notifications, personalization

    var title: String {
        switch self {
        case .main: String(localized: "Einstellungen")
        case .appearance: String(localized: "Darstellung")
        case .habitBehavior: String(localized: "Verhalten")
        case .localModel: String(localized: "Text-Erstellung")
        case .calendar: String(localized: "Kalender & Erinnerungen")
        case .notifications: String(localized: "Mitteilungen")
        case .personalization: String(localized: "Personalisierung")
        }
    }
}

/// "Mehr": iCloud-Status, Darstellung, Graph-Farbe, die beiden
/// Zusammenfassungen (Tag und Woche), Statistik, Archiv, Export/Import und
/// Über/Datenschutz.
///
/// Wohnt auf der MEHR-SEITE (fullScreenCover aus dem Menü oben rechts,
/// siehe ContentView.morePage) — wieder eine eigene Seite mit
/// System-Navigationsleiste. Die zwei seitenartigen Ziele bleiben Knöpfe,
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
    /// Shared app/widget preference for month labels on both graph types.
    let graphShowsMonthLabels: Binding<Bool>
    /// Zählt die eingetroffenen Deep-Links (siehe ContentView). Ein Link ist
    /// eine Absage an das, was gerade offen ist: der Tab wechselt unter dem
    /// Kaufblatt, und ohne dieses Signal bliebe der Nutzer auf einer
    /// Kaufseite sitzen, die zu einem Bereich gehört, den er verlassen hat.
    var routeToken: Int = 0
    var screen: MoreScreen = .main

    @State var summaryDenied = false
    @State var calendarDenied = false
    @State var reminderSyncDenied = false
    @State var weeklyDenied = false
    @State var motivationDenied = false
    @State var notificationDND = NotificationPromptPreference.state
    @State var dndCustomDate = Date().addingTimeInterval(2 * 60 * 60)
    @State var motivationIsWriting = false
    @State var motivationWriteFailed = false
    @State var dndNow = Date()
    @State private var showReminderSetup = false
    @State private var showingFeedback = false
    @State var showWeeklyWeekdayPicker = false
    @State var pickedBackgroundItem: PhotosPickerItem?
    @State var backgroundImageError = false
    @State var showingBackgroundCrop = false
    @State var backgroundImageImportToken = UUID()
    // App-Icon-Auswahl: was der Homescreen gerade zeigt, und ob der letzte
    // Wechsel scheiterte (supportsAlternateIcons == false o. ä.).
    @State var currentIconName: String?
    @State var iconChangeFailed = false
    @State var aliasDraft = ""
    @State var storedAppleName: String?
    @State var storedAppleUserID: String?
    @State var storedAppleEmail: String?
    @State var appleSignInCameBackEmpty = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    /// Startwert = Petrol: bewusst KEINE der 18 Ankerfarben, damit die
    /// Vorschau sofort zeigt, dass frei gewählt und ehrlich gerundet wird.
    @State var freeIconColor: Color = Theme.color(0x0F766E)
    // Eigene Farben: anlegen, bearbeiten, umbenennen, löschen.
    @State var creatingPalette = false
    @State var editingPalette: CustomPalette?
    @State var renamingPalette: CustomPalette?
    @State var renameText = ""
    @State var deletingPalette: CustomPalette?
    /// Das Kaufblatt: `nil` heisst geschlossen. Der Kontext bestimmt nur die
    /// Kopfzeile — vier Zeilen dieser Seite können es öffnen.
    @State var paywall: PaywallContext?
    /// Die Absicht, die das Kaufblatt unterbrochen hat — gesetzt NUR, wenn
    /// der Kauf wirklich vorliegt. Sie wird beim Zufahren des Blatts
    /// ausgeführt: bezahlen und dann vor demselben Schloss stehen ist der
    /// Moment, in dem sich ein Kauf wie ein Fehler anfühlt.
    @State private var purchased: PaywallContext?
    @State var pendingCalendarItemType: HabitItemType = .habit
    @State var calendarPickerType: HabitItemType = .habit
    @State var showCalendarPicker = false
    @State var pendingNativeReminder = false
    @State var nativeSyncCleanupInProgress = false
    @State var nativeSyncCleanupNeedsRetry = false
    @State var nativeSyncCleanupMessage: String?
    @State var showNativeSyncDeleteConfirmation = false
    @State private var proStatus = ProStatus.shared
    /// The local sentence model and its downloads. One instance for the app, so
    /// the picker, the sheet and the reader all see the same progress.
    @State var modelService = LocalModelService()
    @State private var rootTitleProgress: CGFloat = 0
    @State var showingAppearanceCustomize = false
    @Environment(\.palettes) var palettes

    var currentAppearance: AppearancePreferences { store.appearancePreferences }
    /// Der eine Lesepunkt dieser Seite — und ein beobachtbarer (siehe
    /// `ProStatus`). Bewusst KEIN gespiegelter Zustand: der Kauf kann von
    /// einem anderen Blatt oder einem anderen Gerät kommen, und dann müssen
    /// die Schlösser hier trotzdem aufgehen.
    var unlocked: Bool {
        _ = proStatus.unlocked
        return Pro.isUnlocked
    }

    private var localCloudPreferences: CloudPreferences {
        CloudPreferences(calendarSyncHabits: CalendarSync.syncHabits,
                         calendarSyncReminders: CalendarSync.syncReminders,
                         nativeReminderSync: ReminderSync.isEnabled,
                         shakeToReportEnabled: ShakeToReport.isEnabled,
                         notificationDND: NotificationPromptPreference.state)
    }

    func updateCloudPreferences(_ body: (inout CloudPreferences) -> Void) {
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
            case .localModel: localModelSettings
            case .calendar: calendarSettings
            case .notifications: SettingsPage { notificationSettingsSection }
            case .personalization: SettingsPage { personalHeader; personalSection }
            }
        }
        // A presented More screen must not reuse the previous screen's view tree.
        .id(screen)
        .navigationTitle(screen == .main ? "" : screen.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if screen == .main {
                ToolbarItem(placement: .principal) {
                    RootPageCompactTitle(title: screen.title,
                                         progress: rootTitleProgress)
                }
            }
        }
        .pageHeaderChrome(visible: screen != .main)
        .preferredColorScheme(store.appearance.colorScheme)
        // Farbe und Tint noch einmal: ein Blatt ist eine eigene Präsentation
        // und erbt die Umgebung des Bildschirms darunter nicht (siehe
        // ContentView).
        .sheet(isPresented: $creatingPalette) {
            CustomPaletteSheet(store: store)
                .themed(store, palettes: palettes)
                .environment(\.appearanceBackgroundOwned, false)
        }
        .sheet(isPresented: $showingFeedback) {
            FeedbackSheet(store: store, cloudStatus: cloudStatus)
                .themed(store, palettes: palettes)
                .environment(\.appearanceBackgroundOwned, false)
        }
        .onAppear {
            refreshPersonalIdentity()
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
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .sheet(item: $editingPalette) { palette in
            CustomPaletteSheet(store: store, existing: palette)
                .themed(store, palettes: palettes)
                .environment(\.appearanceBackgroundOwned, false)
        }
        .sheet(item: $paywall, onDismiss: resumeAfterPurchase) { context in
            PaywallView(context: context, store: store,
                        onUnlocked: { purchased = context })
                .themed(store, palettes: palettes)
                .environment(\.appearanceBackgroundOwned, false)
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
                .environment(\.appearanceBackgroundOwned, false)
        }
        .sheet(isPresented: $showCalendarPicker) {
            calendarDestinationPicker
                .themed(store, palettes: palettes)
                .environment(\.appearanceBackgroundOwned, false)
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
        .alert(String(localized: "Native Einträge löschen?"),
               isPresented: $showNativeSyncDeleteConfirmation) {
            Button(String(localized: "Alle löschen"), role: .destructive) {
                deleteNativeEntries()
            }
            Button(String(localized: "Abbrechen"), role: .cancel) {}
        } message: {
            Text(String(localized: "Alle von hAiity erstellten Kalender- und Erinnerungs-Einträge werden gelöscht. Die Synchronisierung wird ausgeschaltet."))
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
        ScrollView {
            VStack(alignment: .leading, spacing: store.appearancePreferences.designStyle.cardPadding + 2) {
                RootPageTitle(title: screen.title, compact: true)
                    .padding(.horizontal, -Theme.Metrics.gutter)

                AppSettingsGroup(title: String(localized: "Alltag")) {
                    moreHubRow(title: String(localized: "Mitteilungen"),
                               detail: String(localized: "Zusammenfassungen und Ruhezeiten"),
                               symbol: "bell",
                               identifier: "open-notifications") {
                        onOpen(.notifications)
                    }
                    Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    moreHubRow(title: String(localized: "Verhalten"),
                               detail: String(localized: "Archivierung, Wischaktionen und Zeitzone"),
                               symbol: "hand.draw",
                               identifier: "open-habit-behavior") {
                        onOpen(.habitBehavior)
                    }
                }

                AppSettingsGroup(title: String(localized: "Darstellung")) {
                    moreHubRow(title: String(localized: "Darstellung"), symbol: "paintpalette", identifier: "open-appearance") {
                        onOpen(.appearance)
                    }
                }

                AppSettingsGroup(title: String(localized: "Persönlich & Verbindungen")) {
                    moreHubRow(title: String(localized: "Kalender & Erinnerungen"),
                               symbol: "calendar",
                               identifier: "open-calendar") {
                        onOpen(.calendar)
                    }
                    Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    moreGitHubRow
                    Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    moreAppleAccountRow
                    Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    AppSettingsRow(title: cloudStatus.state.title, detail: cloudStatus.state.detail,
                                   symbol: cloudStatus.state.systemImage) {}
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("cloud-sync-status")
                }

                AppSettingsGroup(title: String(localized: "Daten & Über")) {
                    moreHubRow(title: String(localized: "Import & Export"),
                               detail: String(localized: "Daten exportieren und importieren"),
                               symbol: "arrow.up.arrow.down",
                               identifier: "open-data-transfer") {
                        onOpen(.dataTransfer)
                    }
                    Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    moreHubRow(title: String(localized: "Archiv"),
                               symbol: "archivebox",
                               identifier: "open-archive") {
                        onOpen(.archive)
                    }
                    Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    moreHubRow(title: String(localized: "Über & Datenschutz"),
                               symbol: "lock.shield",
                               identifier: "open-about") {
                        onOpen(.about)
                    }
                    Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                    moreHubRow(title: String(localized: "Fehler melden"), symbol: "bubble.left", identifier: "open-feedback") {
                        showingFeedback = true
                    }
                }
                proSection
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .frame(maxWidth: Theme.Metrics.readableContentWidth).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: ChromeLayout.floatingControlsClearance)
                .accessibilityHidden(true)
        }
        .settingsChrome()
        .coordinateSpace(.named(RootPageTitle.coordinateSpace))
        .onPreferenceChange(RootPageTitleProgressKey.self) { progress in
            guard let progress else { return }
            let collapsed = progress >= 0.5 ? 1 : 0
            if rootTitleProgress != CGFloat(collapsed) {
                rootTitleProgress = CGFloat(collapsed)
            }
        }
        .overlay(alignment: .top) {
            RootPageHeaderBlur(progress: rootTitleProgress)
        }
    }

    var accentColor: Color {
        Theme.accentText(palettes.style)
    }

    private func moreHubRow(title: String,
                            detail: String? = nil,
                            symbol: String,
                            identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AppSettingsRow(title: title,
                           detail: detail,
                           symbol: symbol,
                           showsChevron: true) {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier(identifier)
    }

    private var moreGitHubRow: some View {
        moreGitHubLink
        .padding(.vertical, Theme.Metrics.gap / 2)
    }

    private var moreGitHubLink: some View {
        Button { onOpen(.github) } label: {
            AppSettingsRow(title: String(localized: "GitHub"),
                           detail: moreGitHubConnectionDetail,
                           symbol: "chevron.left.forwardslash.chevron.right",
                           showsChevron: true) {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("open-github-settings")
    }

    private var moreGitHubConnectionDetail: String {
        if github.refreshFeedback == .reauthenticationRequired {
            return String(localized: "Erneut anmelden")
        }
        if github.isRefreshing { return String(localized: "Wird geladen") }
        switch github.phase {
        case .connecting: return String(localized: "Anmeldung läuft")
        case .failed: return String(localized: "Die Verbindung zu GitHub ist fehlgeschlagen.")
        case .connected:
            return github.snapshot.map {
                String(format: String(localized: "Verbunden als %@"), $0.username)
            } ?? String(localized: "Wird geladen")
        case .disconnected: return String(localized: "Noch nicht verbunden")
        }
    }

    private var moreAppleAccountRow: some View {
        moreAppleAccountLink
        .padding(.vertical, Theme.Metrics.gap / 2)
    }

    private var moreAppleAccountLink: some View {
        Button { onOpen(.personalization) } label: {
            AppSettingsRow(title: String(localized: "Personalisierung"),
                           detail: personalDisplayName ?? String(localized: "Wie dürfen wir dich nennen?"),
                           symbol: "person.crop.circle",
                           showsChevron: true) {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("open-account")
    }

    // Die Nacharbeiten-Einstellung (Malen/Auswählen) stand hier — der
    // Malen-Modus ist auf Nutzerwunsch entfernt, die Karte arbeitet immer
    // im Auswählen-Modus. Der alte App-Group-Schlüssel „backfillMode" wird
    // schlicht nicht mehr gelesen.

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


}

/// Export als teilbare JSON-Datei — die Daten entstehen erst beim Teilen.
struct HabitExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("haiity-export.json")
    }
}
