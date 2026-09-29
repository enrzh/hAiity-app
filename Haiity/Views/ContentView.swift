import SwiftUI
import UIKit
import AppIntents
import WidgetKit
#if DEBUG
import os
/// Diagnose-Spur der Such-/Anlegen-Zustandsmaschine (nur Debug): jede
/// Zustandsänderung eine Zeile im os_log, abgreifbar per `log stream`.
let searchTrace = Logger(subsystem: "de.aiity.haiity", category: "searchtrace")
@inline(__always) func trace(_ msg: String) { searchTrace.notice("\(msg, privacy: .public)") }
#else
@inline(__always) func trace(_ msg: String) {}
#endif

private enum CreateAccessibility {
    static let label = String(localized: "Neuer Habit")
    static let identifier = "create-habit"
}

private struct PendingReminderCompletion: Equatable {
    let habitID: UUID
    let day: String
}

/// Haupt-Einstieg. Ab iOS 26 stellt die native TabView die beiden Bereiche
/// Habits und Mehr dauerhaft bereit. Mehr-Unterziele bleiben Blätter über
/// ihrem Tab.
///
/// Ein dritter Tab übernimmt als native Suchaktion den abgesetzten runden
/// Platz rechts. Seine Auswahl wird abgefangen (sofort zurück auf den
/// vorherigen Inhalts-Tab) und öffnet das Suchfeld. Der Anlegen-Knopf sitzt
/// oben rechts; seine Seite zoomt ab iOS 18 aus genau diesem Toolbar-Plus.
/// Damit kommen Halten-Blase, Scroll-Minimieren
/// (`.tabBarMinimizeBehavior(.onScrollDown)`) und das geteilte Glas vom
/// SYSTEM, nicht aus einer Nachbildung.
///
/// Unter iOS 26 (17–25) bleibt die selbstgebaute Leiste als Fallback:
/// linksbündige Glas-Kapsel für Habits und Mehr plus der + rechts in der
/// Ecke, mit dem gerechneten Zusammenziehen beim Scrollen.
struct ContentView: View {
    @State private var store = HabitStore(loadFromDisk: false)
    @State private var github = GitHubContributionStore()
    @State private var graphShowsMonthLabels = GitHubPreferences.showsMonthLabels
    /// iCloud-Spiegel. Der lokale Stand in `store` ist die Wahrheit; das hier
    /// trägt ihn nur zur Apple-ID hinüber (siehe CloudSync).
    @State private var cloud = CloudSync()
    @State private var cloudStatus = CloudSyncStatus()
    /// Fasst schnelle Folgeänderungen zu EINEM Upload zusammen.
    @State private var pushes = PushDebouncer()
    /// Coalesces notification, shortcut and native-store maintenance after a
    /// burst of local edits without delaying the local habit update. The delay
    /// is longer than a sheet dismiss so Save/Done can return to Habits
    /// before EventKit and notification work run.
    @State private var maintenance = PushDebouncer(delay: .milliseconds(500))
    @State private var pendingCalendarSync: CalendarSyncScope?
    @State private var editing: Habit?
    @State private var pendingDelete: Habit?
    @State private var earlyReminderCompletion: PendingReminderCompletion?
    @State private var showAdd = false
    /// `showAdd` ist nur der Praesentationswunsch. Erst `createPage.onAppear`
    /// belegt, dass ein Cover wirklich da ist und ein `onDismiss` schuldet.
    @State private var createCover = CreateCoverPresentation()
    /// Das Kaufblatt: EIN optionaler Zustand statt Flagge plus Kontext, die
    /// auseinanderlaufen können. `nil` heisst geschlossen; der Kontext ändert
    /// nur die Kopfzeile, nie das Angebot.
    @State private var paywall: PaywallContext?
    /// Bleibt bis zum `onDismiss` des Kaufblatts wahr — dieselbe
    /// Buchführung wie beim Mehr-Blatt: erst danach darf eine Route ihre
    /// eigene Präsentation starten.
    @State private var paywallIsPresented = false
    /// Die Absicht, die das Kaufblatt unterbrochen hat — gesetzt NUR, wenn
    /// der Kauf wirklich vorliegt.
    @State private var purchasedIntent: PaywallContext?
    /// Zählt eingetroffene Deep-Links. Die Bereiche, die ihr eigenes
    /// Kaufblatt halten (Mehr, Statistik), räumen es daran weg: ein Link
    /// wechselt den Bereich DARUNTER, und ein stehen gelassenes Blatt wäre
    /// eine Sackgasse.
    @State private var routeToken = 0
    @State private var syncStatus = ""
    /// Wann die App zuletzt aktiv wurde. In den ersten Sekunden danach wird
    /// KEIN Sync-Fehler eingeblendet: CloudKit wirft beim Start und beim
    /// Aufwachen routinemäßig kurzlebige Fehler, die sich selbst heilen —
    /// eine Pille dafür ist Lärm (vom Gerät gemeldet: „split second of
    /// icloud error"). Echte Fehler zeigen sich beim nächsten Abgleich nach
    /// dem Fenster erneut und DANN sichtbar.
    @State private var becameActiveAt = Date.distantPast
    /// Auswahl der Bereiche. In der nativen Tableiste wird `.search` im
    /// selben Umlauf auf den zuvor gewählten echten Tab zurückgesetzt und
    /// öffnet das Suchfeld.
    @State private var nativeTab: AppTab = .habits
    /// Tabs whose content has been built at least once. Building only the
    /// selected tab is a startup win — three pages of grids and cards are far
    /// too much to construct during the first frame — but DESTROYING the
    /// unselected ones throws away their @State, and that is what made the
    /// Statistik page flash on every visit: the snapshot starts nil again, the
    /// placeholder goes up, and the real page pops in over it. Once a tab has
    /// been paid for, keeping it in the tree costs nothing and removes the
    /// rebuild, so returning to it is instant.
    @State private var builtTabs: Set<AppTab> = [.habits]
    @State private var proStatus = ProStatus.shared
    /// The scene's first active callback can arrive before the async boot
    /// task has installed its local state and maintenance pipeline.
    @State private var initialBootReady = false
    @State private var hasSeenInitialActivation = false
    /// The first active callback belongs to launch, not a foreground resume.
    /// Native and cloud maintenance is allowed only after the scene actually
    /// leaves the foreground once.
    @State private var hasEnteredBackground = false
    @State private var startupMaintenanceTask: Task<Void, Never>?
    @State private var postLaunchHydrationTask: Task<Void, Never>?
    /// Native and notification maintenance must never compete with the first
    /// interactive frame or with a newer foreground activation.
    @State private var integrationsReady = false
    /// Reinstall cleanup touches EventKit synchronously. Keep it out of the
    /// first startup pass and retry it on the next real foreground instead.
    @State private var nativeSyncRecoveryPending = false
    @State private var showReminderSetup = false
    @State private var nativeSyncCleanupNeedsRetry = false
    @State private var nativeSyncCleanupMessage: String?
    /// Das Melde-Blatt (Schütteln). Es hängt hier oben, weil die Geste überall
    /// gilt — sie gehört keinem Bereich, sondern der App.
    @State private var showFeedback = false
    @State private var showSpeakToCreate = false
    /// Wann das Melde-Blatt zuletzt zuging. Ein Schütteln endet oft mit einem
    /// Nachschütteln (die Hand hört später auf als der Kopf) — ohne diese
    /// Ruhezeit spränge das eben geschlossene Blatt sofort wieder auf.
    @State private var feedbackClosedAt = Date.distantPast
    /// Mehr-Unterziele aus Deep-Links auf dem Fallback vor iOS 26.
    @State private var moreSheet: MoreRoute?
    /// Unterziel des nativen Mehr-Tabs, als Blatt über diesem Tab.
    @State private var morePageRoute: MoreRoute?
    /// Bleibt bis zum gemeinsamen sheet-onDismiss wahr. Damit startet eine
    /// Ersatzroute weder im Abgang des Fallback- noch des nativen Blatts.
    @State private var moreSheetIsPresented = false
    @State private var moreRoutePresentationTask: Task<Void, Never>?
    /// Das Unterziel bleibt während des Abgangs bekannt. So kann dieselbe
    /// Route vom bereits sichtbaren Ziel unterschieden werden, ohne neu zu
    /// präsentieren.
    @State private var presentedMoreDestination: AppMoreDestination?
    /// Wartet die Tab-Auswahl ab, bevor ein Deep-Link eine Präsentation
    /// auslöst. Ein neuer Link ersetzt eine noch ausstehende Präsentation.
    @State private var routePresentationTask: Task<Void, Never>?
    /// Sperrt bereits eingereihte Sucharbeit eines älteren Deep-Links.
    @State private var routeWork = RouteWork()
    /// A widget route carries the selected habit. The list consumes this
    /// once its rows are mounted and scrolls to the stable UUID anchor.
    @State private var requestedHabitID: UUID?
    /// Genau die letzte noch nicht angewandte Route. Beide Präsentations-
    /// callbacks prüfen ihren Generationstoken, bevor sie sie weiterreichen.
    @State private var pendingRoute: RouteWork.Item?
    /// Die synchronisierte Auswahl der Statistik-Karten und der festen
    /// kompakten Darstellung. Scrollen schreibt diesen Zustand nie.
    @State private var viewPreferences = ViewPreferencesStore()
    @State private var search = ""
    /// Keeps keystrokes out of the large lazy list until the user pauses.
    @State private var committedSearch = ""
    @State private var searchCommitTask: Task<Void, Never>?
    @State private var habitFilter = HabitListFilter.restored()
    @State private var progressNow = Date.now
    /// Nur fuer die iOS-17...25-Fallback-Suche; iOS 26+ zeigt das Feld nativ
    /// dauerhaft auf der dedizierten Suchseite.
    @State private var searching = false
    /// The search page owns focus. Selecting it shows the field; selecting the
    /// already-visible Search tab again is the explicit keyboard request.
    @FocusState private var searchFieldFocused: Bool
    /// Inline custom reorder on the habits list — not list `EditMode`.
    @State private var habitSortingActive = false
    @State private var sortingDraggedID: UUID?
    @State private var rootTitleProgress: CGFloat = 0
    /// Der Rückgängig-Toast. Höchstens einer, der Letzte gewinnt — siehe
    /// UndoToastState.
    @State private var undo = UndoToastState()
    /// Offene Nacharbeiten-Karte; nil = keine. Sie hält NUR die Kennung des
    /// Habits, nicht das Habit selbst: nach jedem Schreibvorgang muss die
    /// Karte den frischen Stand aus dem Store zeigen, nicht eine Kopie von
    /// vor dem Tippen.
    @State private var backfill: BackfillRequest?
    /// Hält die Glasteile unten zusammen: gleiche ID vor und nach dem
    /// Zusammenziehen = ein Morph statt zweier Blenden. (Nur Fallback-Leiste.)
    @Namespace private var glassNamespace
    /// Namensraum der Anlegen-Zoom-Transition: die Anlegen-Seite wächst aus
    /// dem Anlegen-Knopf (iOS 18+).
    @Namespace private var createZoomNamespace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Zusammengezogenes Chrom (Fallback-Leiste) und verdichtete Karten.
    /// Dieser Zustand ist ausschließlich eine persistente Nutzerwahl.
    private var collapsed: Bool { viewPreferences.compactMode }

    private var effectivePalettes: PaletteBook {
        let unlocked = Pro.isUnlocked
        return unlocked ? store.palettes : store.palettes.withoutCustoms
    }

    /// The store retains the complete payload; the current entitlement decides
    /// which active entries the main app exposes.
    private var visibleActiveHabits: [Habit] {
        _ = proStatus.unlocked
        return ProGate.visibleActiveHabits(store.activeHabits,
                                           unlocked: Pro.isUnlocked)
    }

    private var visibleActiveTrackedHabits: [Habit] {
        visibleActiveHabits.filter(\.isTrackedHabit)
    }

    private var effectivePaletteStyle: PaletteStyle {
        effectivePalettes.style
    }

    private var githubUsernameBinding: Binding<Bool> {
        Binding(get: { store.githubShowsUsername },
                set: { store.githubShowsUsername = $0 })
    }

    private var githubMonthLabelsBinding: Binding<Bool> {
        Binding(get: { graphShowsMonthLabels },
                set: { value in
                    graphShowsMonthLabels = value
                    GitHubPreferences.setShowsMonthLabels(value,
                                                          in: GitHubPreferences.defaults)
                })
    }

    /// Vereinigungs-Kennung der Glasteile unten. Teilen zwei Teile dieselbe,
    /// rechnet iOS ihr Glas als EINE Form: zusammengezogen werden Umschalter
    /// und Anlegen-Knopf zu einem Blob, sonst bleibt jeder eine eigene
    /// Scheibe an seinem Rand.
    ///
    /// Die Mehr-Tafel steht bewusst gar nicht in dieser Vereinigung.
    /// Ausprobiert und wieder ausgebaut: verschmilzt die Tafel mit der
    /// Kapsel, gewinnt die große Fläche — die Leiste verliert ihre eigene
    /// Form, und der Anlegen-Knopf steht blass auf dem Tafelglas. Der
    /// Eindruck „wächst aus der Leiste" trägt die Animation (Skalierung mit
    /// Anker auf dem Mehr-Segment), nicht ein gemeinsamer Glaskörper.
    private func chromeUnion(_ solo: String) -> String {
        collapsed ? "chrome-blob" : solo
    }

    var body: some View {
        #if DEBUG
        FrameProbe.shared.mark("CV.body")
        #endif
        return shell
            // Die Nacharbeiten-Karte steckt IM jeweiligen Shell-Zweig (siehe
            // `nativeShell` bzw. den Fallback darunter), nicht mehr hier
            // über allem: sie muss ÜBER der Liste, aber UNTER dem
            // Rückgängig-Toast liegen. Als Overlay an dieser Stelle lag ihr
            // Vorhang über den schwebenden Pillen der nativen Leiste — der
            // Toast war sichtbar, aber sein Tipp landete im Vorhang und
            // SCHLOSS die Karte, statt zurückzunehmen (nachgemessen im
            // Simulator; genau das Zurück, das die Kommentare versprechen).
            .overlay(alignment: .bottom) { nativeToastOverlay }
            // Die drei Zeilen sind das ganze Theming-Gerüst: das Schema wird
            // fürs FENSTER gesetzt (Blätter inklusive), die Palette reist als
            // Umgebungswert bis in jede Rasterzelle, und der Tint zieht die
            // System-Steuerelemente mit. Alle drei hängen am Store, damit ein
            // Umstellen in „Mehr" sofort durchschlägt.
            .preferredColorScheme(store.appearance.colorScheme)
            .environment(\.palettes, effectivePalettes)
            .environment(\.appearancePreferences, store.appearancePreferences)
            // accentText statt accent: die Markenfarbe hat auf hellem Grund
            // nur ~3,4:1 — als Schrift/Symbolfarbe ist das zu wenig.
            .tint(Theme.accentText(effectivePaletteStyle))
            .onOpenURL { handleDeepLink($0) }
            .onReceive(NotificationCenter.default.publisher(
                for: NotificationActionRouter.pendingDidChange)) { _ in
                schedulePendingNotificationAction()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NotificationDeliveryIssueCenter.pendingDidChange)) { _ in
                schedulePendingNotificationDeliveryIssue()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: HomeShortcuts.pendingDidChange)) { _ in
                schedulePendingShortcutLink()
            }
            // Blätter sind eine EIGENE Präsentation: Farbe und Tint von oben
            // kommen dort nicht an (nachgemessen — die Farbwahl im Blatt zeigte
            // sonst Grün, während die App längst in einer eigenen Farbe lief).
            // Deshalb beides hier noch einmal, an EINER Stelle je Blatt.
            // ANLEGEN ist eine SEITE, kein Half-Sheet mehr — dasselbe Muster
            // wie „Mehr": ein fullScreenCover, das ab iOS 18 mit der
            // Zoom-Transition aus dem Anlegen-Knopf wächst und
            // beim Schließen dorthin zurückschrumpft; X oben links schließt.
            // Der Sprachknopf liegt am SHELL, nicht auf einer Seite: er soll auf
            // jedem Tab stehen, und an vier Stellen eine Kopie zu bauen wäre die
            // übliche Art, wie so etwas auseinanderläuft. Er sitzt in derselben
            // Trailing-Spalte wie der schwebende Suchknopf, direkt DARÜBER — als
            // untergeordneter Begleiter, nicht als zweite Hauptaktion.
            .overlay(alignment: .bottomTrailing) {
                if viewPreferences.dictateCreateEnabled { speakButton }
            }
            .sheet(isPresented: $showSpeakToCreate) {
                SpeakToCreateSheet(store: store)
                    .themed(store, palettes: effectivePalettes)
                    .environment(\.appearanceBackgroundOwned, false)
            }
            .fullScreenCover(isPresented: $showAdd,
                             onDismiss: deliverPendingCreateDismissalRoute) {
                createPage.onAppear { createCoverDidPresent() }
            }
            // Das Kaufblatt hängt hier oben, weil das Limit an VIER Stellen
            // zuschlagen kann (Toolbar-+, Leerzustand, Fallback-Chrom,
            // Deep-Link). Ein Blatt je Einstieg wären vier Wege, es zu
            // verlieren — und vier Stellen, an denen es anders aussieht.
            //
            // Es hängt MIT in der Routen-Zustandsmaschine (onDismiss →
            // advancePendingRoute): ein Deep-Link, der eintrifft, während es
            // offen steht, schaltet sonst den Bereich darunter um und lässt
            // den Nutzer auf der Kaufseite sitzen.
            .sheet(item: $paywall,
                   onDismiss: deliverPendingPaywallDismissalRoute) { context in
                PaywallView(context: context, store: store,
                            onUnlocked: { purchasedIntent = context })
                    .themed(store, palettes: effectivePalettes)
                    .environment(\.appearanceBackgroundOwned, false)
                    .onAppear { paywallDidPresent(context) }
            }
            .sheet(item: $editing) {
                EditHabitSheet(store: store, existing: $0)
                    .themed(store, palettes: effectivePalettes)
                    .environment(\.appearanceBackgroundOwned, false)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                String(localized: "Vor Termin erledigen?"),
                isPresented: Binding(
                    get: { earlyReminderCompletion != nil },
                    set: { if !$0 { earlyReminderCompletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Erledigen")) {
                    confirmEarlyReminderCompletion()
                }
                .accessibilityIdentifier("reminder-early-completion-confirm")
                Button(String(localized: "Abbrechen"), role: .cancel) {
                    earlyReminderCompletion = nil
                }
            } message: {
                Text(String(localized: "Der Termin liegt noch in der Zukunft."))
            }
            .confirmationDialog(
                String(localized: "Eintrag löschen?"),
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete) { habit in
                    Button(String(localized: "Löschen"), role: .destructive) {
                        store.remove(habit.id)
                        pendingDelete = nil
                    }
                    Button(String(localized: "Abbrechen"), role: .cancel) {}
                } message: { habit in
                    Text(String(localized: "„\(habit.name)“ und die komplette Historie werden gelöscht. Das lässt sich nicht rückgängig machen."))
                }
            // Direkte Unterziele bleiben Blätter über dem aktuell sichtbaren
            // Bereich. Mehr-Zeilen präsentieren über `morePageRoute`.
            .sheet(item: $moreSheet,
                   onDismiss: deliverPendingMoreDismissalRoute) { route in
                NavigationStack {
                    moreSheetRoot(fallback: route)
                        .navigationDestination(for: MoreRoute.self, destination: moreDestination)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    dismissMoreSheet()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.footnote.weight(.semibold))
                                        .frame(width: Theme.Metrics.hit,
                                               height: Theme.Metrics.hit)
                                        .contentShape(Circle())
                                }
                                .accessibilityLabel(String(localized: "Fertig"))
                                    .accessibilityIdentifier("close-more-sheet")
                            }
                        }
                }
                .themed(store, palettes: effectivePalettes)
                .environment(\.appearanceBackgroundOwned, false)
                .onAppear { moreSheetDidPresent(route) }
            }
            .fullScreenCover(isPresented: $showReminderSetup) {
                ReminderSetupView(isPresented: $showReminderSetup, store: store)
                    .themed(store, palettes: effectivePalettes)
                    .environment(\.appearanceBackgroundOwned, false)
            }
            // Schütteln meldet einen Fehler — für JEDEN Nutzer, nicht nur für
            // den Entwickler. Die Geste hängt an der Wurzel, weil sie überall
            // gilt; ob daraus ein Blatt wird, entscheidet `handleShake()`.
            .onShake { handleShake() }
            .onReceive(NotificationCenter.default.publisher(for: ShakeToReport.didChange)) { _ in
                guard store.cloudPreferences?.shakeToReportEnabled != ShakeToReport.isEnabled else {
                    return
                }
                store.updateCloudPreferences(fallback: localCloudPreferences) {
                    $0.shakeToReportEnabled = ShakeToReport.isEnabled
                }
            }
            .sheet(isPresented: $showFeedback,
                   onDismiss: { feedbackClosedAt = .now }) {
                FeedbackSheet(store: store, cloudStatus: cloudStatus)
                    .themed(store, palettes: effectivePalettes)
                    .environment(\.appearanceBackgroundOwned, false)
            }
            .task {
                #if DEBUG
                if let fixtureStore = DesignFixture.makeStore() {
                    store = fixtureStore
                    habitFilter = HabitListFilter()
                    Pro.setDebugUnlocked(true)
                    handleLaunchScreenArgument()
                    if FrameProbe.enabled { FrameProbe.shared.start() }
                    return
                }
                #endif
                let diskLoadSignpost = StartupMetrics.begin("diskLoad")
                await store.loadFromDisk()
                StartupMetrics.end("diskLoad", id: diskLoadSignpost)
                // Give SwiftUI one scheduling point after disk hydration so
                // the first populated frame can render immediately.
                await Task.yield()
                StartupMetrics.event("localDataReady")
                becameActiveAt = .now
                #if DEBUG && targetEnvironment(simulator)
                // Keep deterministic simulator routes independent of startup
                // sync, which can legitimately wait on iCloud.
                handleLaunchScreenArgument()
                // Seed interaction fixtures before boot as well. Boot may
                // wait on iCloud, while UI tests need their row in the first
                // rendered list.
                //
                // SIMULATOR ONLY, deliberately. These hooks write into the real
                // App Group store: a "UI test reminder" appears in the person's
                // list and the stats card preferences are overwritten. Debug
                // alone was not enough — a Debug build on a real phone is still
                // the person's own data, and the comment above already said
                // "simulator routes". DesignFixture makes the same guard.
                handleLaunchTestData()
                #endif
                await boot()
                StartupMetrics.event("bootComplete")
                // A background transition that happened while the process was
                // still booting is not a resume of the mounted app.
                hasEnteredBackground = false
                #if DEBUG && targetEnvironment(simulator)
                // Seeded interaction fixtures must be written after the
                // initial iCloud merge, otherwise a startup reload can race
                // the test fixture and hide the item being exercised.
                handleLaunchTestData()
                #endif
                schedulePendingNotificationAction()
                schedulePendingNotificationDeliveryIssue()
                schedulePendingShortcutLink()
                schedulePostLaunchHydration()
                await Task.yield()
                StartupMetrics.event("firstInteractiveFrame")
                #if DEBUG
                if FrameProbe.enabled { FrameProbe.shared.start() }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    guard initialBootReady else {
                        hasSeenInitialActivation = true
                        return
                    }
                    guard hasSeenInitialActivation else {
                        hasSeenInitialActivation = true
                        return
                    }
                    guard hasEnteredBackground else { return }
                    progressNow = .now
                    if DesignFixture.scenario != nil { return }
                    becameActiveAt = .now
                    schedulePendingNotificationAction()
                    schedulePendingNotificationDeliveryIssue()
                    schedulePendingShortcutLink()
                    // Widget-Intent kann data.json extern geändert haben —
                    // purer Re-Read (No-op bei unveränderter mtime).
                    store.reloadFromDisk()
                    viewPreferences.adoptRemote(store.data.viewPreferences)
                    NotificationPresenter.configureQuickActions(
                        enabled: viewPreferences.preferences.notificationActionsEnabled,
                        choices: viewPreferences.preferences.notificationActions.slots)
                    // Konto kann sich ausserhalb der App geändert haben
                    // (an-/abgemeldet), und das andere Gerät kann gehakt
                    // haben, während diese App im Hintergrund lag.
                    cloudStatus.refresh()
                    postLaunchHydrationTask?.cancel()
                    scheduleForegroundMaintenance()
                    Task { await github.resumeOrRefresh(forced: true) }
                } else {
                    if phase == .background { hasEnteredBackground = true }
                    startupMaintenanceTask?.cancel()
                    postLaunchHydrationTask?.cancel()
                    Task { await maintenance.cancel() }
                }
            }
            .onChange(of: proStatus.unlocked) { old, new in
                applyCloudPreferences()
                handleProEntitlementChange(old: old, new: new)
            }
            .onChange(of: showAdd) { _, open in
                trace("showAdd=\(open) tab=\(nativeTab)")
                guard open else { return }
                if #unavailable(iOS 26) { searching = false }
                // Dieselbe Hygiene wie beim Öffnen der Mehr-Seite: das Cover
                // verdeckt Liste, Toast und Karte vollständig.
                undo.clear()
                backfill = nil
            }
            .onChange(of: search) { _, query in
                if !query.isEmpty { setHabitSortingActive(false) }
                searchCommitTask?.cancel()
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                searchCommitTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { committedSearch = trimmed }
                }
            }
            .onChange(of: habitFilter) { _, filter in
                if !filter.isEmpty { setHabitSortingActive(false) }
            }
            .onChange(of: habitFilter.todayOnly) { _, todayOnly in
                HabitListFilterPreferences.persistTodayOnly(todayOnly)
            }
            .onChange(of: nativeTab) { old, tab in
                trace("nativeTab \(old)->\(tab) showAdd=\(showAdd)")
                builtTabs.insert(tab)
                guard old == .search, tab != .search else { return }
                searchFieldFocused = false
                if #unavailable(iOS 26) { searching = false }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    search = ""
                    committedSearch = ""
                }
            }
    }

    /// One owner for "show the keyboard on the search tab". Both the deep-link
    /// route and a hand tap on the tab go through here, so the two paths cannot
    /// drift apart.
    private func focusSearchField() {
        guard #available(iOS 26, *) else {
            searching = true
            return
        }
        guard #available(iOS 27, *) else { return }
        DispatchQueue.main.async { searchFieldFocused = true }
    }

    // MARK: – Sprachknopf

    /// The standing "say it instead of typing it" control.
    ///
    /// Sized to the same 52 pt circle as the app's other floating controls and
    /// offset by the same tab-bar clearance, so it sits in the band's bottom
    /// row rather than on top of the tab bar. Hidden while a sheet or the
    /// create page is up: a floating control over a modal is a tap target with
    /// nothing behind it.
    @ViewBuilder
    /// The on-device writing entry point, on the same glass as the rest of the
    /// floating chrome.
    ///
    /// It was a microphone, which said "record a voice note" and understated what
    /// this actually is: a sentence that becomes a habit, worked out on the
    /// device. A sparkle says that, and it is distinct from the microphone inside
    /// the sheet and from the keyboard's own dictation key, so the three never get
    /// confused for each other.
    private var speakButton: some View {
        if !showAdd, !showSpeakToCreate, paywall == nil, !showFeedback,
           viewPreferences.dictateCreateEnabled {
            Button {
                showSpeakToCreate = true
                Theme.Haptics.select()
            } label: {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText(effectivePaletteStyle))
                    .frame(width: Theme.Metrics.control, height: Theme.Metrics.control)
                    .modifier(ChromeGlass(id: "speak-button",
                                          namespace: glassNamespace,
                                          kind: .circle,
                                          union: "speak-button"))
                    // No accent tint. A tinted glass circle is a green button with
                    // a material behind it, which is not what this is: the tint
                    // filled the shape and the glass stopped being visible at all.
                    // The sparkle keeps the accent, so the colour still says
                    // "writing", and the bar underneath is neutral so the search
                    // below stays the louder of the two.
                    .overlay(Circle().strokeBorder(
                        Theme.accentText(effectivePaletteStyle).opacity(0.14),
                        lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Aus einem Satz anlegen"))
            .accessibilityIdentifier("speak-to-create")
            // Trailing column, directly above the control it pairs with. The
            // numbers come from the layout constants so the stack survives a
            // change to either diameter.
            .padding(.trailing, ChromeLayout.speakButtonTrailing)
            .padding(.bottom, ChromeLayout.speakButtonBottom)
        }
    }

    // MARK: – Bereiche

    /// Ab iOS 26 die NATIVE Tableiste, darunter die Fallback-Leiste (das
    /// bisherige selbstgebaute Chrom, siehe `legacyBottomChrome`).
    @ViewBuilder
    private var shell: some View {
        if #available(iOS 26, *) {
            nativeShell
        } else {
            ZStack {
                AppearanceBackground(preferences: store.appearancePreferences)
                fallbackTabLayer(.stats) { fallbackStatsContent }
                fallbackTabLayer(.habits) { habitsStack }
                fallbackTabLayer(.more) { fallbackMoreContent }
            }
            .environment(\.appearanceBackgroundOwned, true)
            // Über der Liste, unter dem Fallback-Chrom (das `body` DANACH
            // auflegt): der Rückgängig-Toast im Chrom-Stapel bleibt über der
            // offenen Karte antippbar.
            .sheet(item: $backfill) { request in backfillEditor(request) }
            .overlay(alignment: .bottom) { legacyBottomChrome }
        }
    }

    /// Feste ZStack-Positionen halten beide NavigationStacks samt Scroll- und
    /// lokalem View-Zustand am Leben. Opazitaet 0 spart das Zeichnen des
    /// inaktiven Baums; Treffer und Accessibility folgen derselben Auswahl.
    private func fallbackTabLayer<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let state = AppTabLayerState(tab: tab, selectedTab: nativeTab)
        return content()
            .opacity(state.opacity)
            .allowsHitTesting(state.allowsHitTesting)
            .accessibilityHidden(state.accessibilityHidden)
            .zIndex(state.zIndex)
    }

    /// Ab iOS 26 ist die Leiste vollständig nativ: drei Inhalts-Tabs in der
    /// Kapsel (Statistik, Habits, Mehr) plus der ECHTE Such-Tab als
    /// abgesetzter Kreis rechts — das Fotos-Muster.
    ///
    /// **Der Such-Tab ist jetzt eine echte Suche.** Seine Such-Modifikatoren
    /// hängen am eigenen Tab-Inhalt und filtern nur die Suchseite. Am
    /// `TabView` bleibt lediglich die native Aktivierungslogik, damit der
    /// zweite Tipp auf den ausgewählten Search-Tab das Feld öffnet.
    @available(iOS 26, *)
    @ViewBuilder
    private var nativeShell: some View {
        if #available(iOS 27, *) {
            splitShell
        } else {
            searchRoleShell
        }
    }

    /// iOS 26's only native split affordance is the Search role.
    @available(iOS 26, *)
    private var searchRoleShell: some View {
        ZStack {
            TabView(selection: $nativeTab) {
                Tab(String(localized: "Statistik"), systemImage: "chart.bar",
                    value: AppTab.stats) {
                    nativeTabRoot { nativeTabContent(.stats) { statsTabContent } }
                }
                Tab(String(localized: "Habits"), systemImage: "square.grid.2x2",
                    value: AppTab.habits) {
                    nativeTabRoot { nativeTabContent(.habits) { habitsTabContent } }
                }
                Tab(String(localized: "Mehr"), systemImage: "ellipsis",
                    value: AppTab.more) {
                    nativeTabRoot { nativeTabContent(.more) { moreTabContent } }
                }
                // The search tab owns a persistent native search field.
                Tab(String(localized: "Suchen"), systemImage: "magnifyingglass",
                    value: AppTab.search, role: .search) {
                    nativeTabRoot { searchTabContent }
                }
            }
            .tabViewSearchActivation(.automatic)
            .tabBarMinimizeBehavior(.onScrollDown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// iOS 27's prominent role keeps Search separate without a custom tab-bar
    /// overlay. Older Xcode Cloud toolchains compile the same layout with the
    /// native search role because `TabRole.prominent` is not in their SDK.
    @available(iOS 27, *)
    private var splitShell: some View {
        TabView(selection: $nativeTab) {
            Tab(String(localized: "Statistik"), systemImage: "chart.bar",
                value: AppTab.stats) {
                nativeTabRoot { nativeTabContent(.stats) { statsTabContent } }
            }
            Tab(String(localized: "Habits"), systemImage: "square.grid.2x2",
                value: AppTab.habits) {
                nativeTabRoot { nativeTabContent(.habits) { habitsTabContent } }
            }
            Tab(String(localized: "Mehr"), systemImage: "ellipsis",
                value: AppTab.more) {
                nativeTabRoot { nativeTabContent(.more) { moreTabContent } }
            }
#if compiler(>=6.4)
            Tab(String(localized: "Suchen"), systemImage: "magnifyingglass",
                value: AppTab.search, role: .prominent) {
                nativeTabRoot { searchTabContent }
            }
#else
            Tab(String(localized: "Suchen"), systemImage: "magnifyingglass",
                value: AppTab.search, role: .search) {
                nativeTabRoot { searchTabContent }
            }
#endif
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    @available(iOS 26, *)
    private func nativeTabRoot<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.appearanceBackgroundOwned, true)
    }

    /// The native tab host can retain inactive tab values. Do not construct
    /// their graph-heavy view trees until that tab is selected.
    @ViewBuilder
    private func nativeTabContent<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if nativeTab == tab || builtTabs.contains(tab) { content() }
    }

    /// The native tab host can add an opaque backdrop around a NavigationStack.
    /// Put the wallpaper in the stack's actual page root so Lists and the
    /// navigation header cannot cover it with a system page color.
    @available(iOS 26, *)
    private func nativePageRoot<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            AppearanceBackground(preferences: store.appearancePreferences)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.appearanceBackgroundOwned, true)
    }

    /// The native tab bar paints outside a TabView's content overlay. Keep
    /// feedback in the root overlay and reserve the full expanded-bar height;
    /// otherwise iOS 27 can draw the bar over a toast during its resize.
    @ViewBuilder
    private var nativeToastOverlay: some View {
        if #available(iOS 26, *), !searching {
            floatingPills
                .safeAreaPadding(.bottom,
                                  ChromeLayout.toastBottomPadding(nativeBar: true,
                                                                  searching: searching))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .zIndex(200)
        }
    }

    /// Der Statistik-Tab: die frühere Mehr-Unterseite als eigener Bereich.
    @available(iOS 26, *)
    private var statsTabContent: some View {
        NavigationStack {
            nativePageRoot {
                StatsView(store: store, viewPreferences: viewPreferences,
                          routeToken: routeToken)
            }
        }
        .navigationChrome()
    }

    /// Der Inhalt des Such-Tabs: kompakte Treffer ohne Raster. Leerer
    /// Suchbegriff zeigt die volle Liste — der Tab ist damit auch ohne
    /// Eingabe kein weißes Loch. Die native Suchleiste bleibt wie im App Store
    /// an der Navigation verankert und reduziert sich beim Scrollen selbst.
    @available(iOS 26, *)
    private var searchTabContent: some View {
        NavigationStack {
            nativePageRoot {
                // The native TabView may keep non-selected tabs alive. Do
                // not keep a second graph-heavy list mounted off screen.
                if nativeTab == .search {
                    Group {
                        if visibleActiveHabits.isEmpty {
                            emptyState
                        } else {
                            searchList
                        }
                    }
                    .navigationTitle(String(localized: "Suchen"))
                    .navigationBarTitleDisplayMode(.large)
                    .pageHeaderChrome()
                }
            }
        }
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(String(localized: "Habits und Erinnerungen durchsuchen")))
        .searchFocused($searchFieldFocused)
        .navigationChrome()
    }

    @available(iOS 26, *)
    private var searchList: some View {
        List {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(searchResults) { habit in
                    searchRow(for: habit)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, Theme.Metrics.rootTitleInset, for: .scrollContent)
        .softScrollEdges()
    }

    /// Der Inhalt des Habits-Tabs — EINE Quelle für beide Leisten-Varianten.
    @available(iOS 26, *)
    private var habitsTabContent: some View {
        NavigationStack {
            nativePageRoot { habitsScreen }
        }
        // Die Nacharbeiten-Karte ÜBER der Liste, aber UNTER den
        // schwebenden Pillen: der Rückgängig-Toast ist das Zurück zu
        // genau dem, was die Karte gerade geschrieben hat, und muss
        // bei offener Karte antippbar bleiben — dieselbe Schichtung
        // wie im Fallback (Karte unter dem Chrom-Stapel).
        .sheet(item: $backfill) { request in backfillEditor(request) }
        .navigationChrome()
    }

    @available(iOS 26, *)
    private var moreTabContent: some View {
        NavigationStack {
            nativePageRoot {
                MoreView(store: store, github: github, cloudStatus: cloudStatus,
                         statsCards: viewPreferences,
                         onOpen: presentMoreSheet,
                         graphShowsMonthLabels: githubMonthLabelsBinding,
                         routeToken: routeToken)
            }
        }
        .navigationChrome()
        .sheet(item: $morePageRoute,
               onDismiss: deliverPendingMoreDismissalRoute) { route in
            NavigationStack {
                moreSheetRoot(fallback: route)
                    // Die versteckte Tür in „Über" SCHIEBT den
                    // Entwicklerbereich in dieses Blatt (siehe MoreRoute).
                    .navigationDestination(for: MoreRoute.self, destination: moreDestination)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                dismissMoreSheet()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.footnote.weight(.semibold))
                                    .frame(width: Theme.Metrics.hit,
                                           height: Theme.Metrics.hit)
                                    .contentShape(Circle())
                            }
                            .accessibilityLabel(String(localized: "Fertig"))
                                .accessibilityIdentifier("close-more-sheet")
                        }
                    }
            }
            .id("more-sheet-\(route)")
            .navigationChrome()
            .themed(store, palettes: effectivePalettes)
            .environment(\.appearanceBackgroundOwned, false)
            .onAppear { moreSheetDidPresent(route) }
        }
    }

    private var fallbackMoreContent: some View {
        NavigationStack {
            MoreView(store: store, github: github, cloudStatus: cloudStatus,
                     statsCards: viewPreferences,
                     onOpen: presentMoreSheet,
                     graphShowsMonthLabels: githubMonthLabelsBinding,
                     routeToken: routeToken)
        }
        .navigationChrome()
    }

    private var fallbackStatsContent: some View {
        NavigationStack {
            StatsView(store: store, viewPreferences: viewPreferences,
                      routeToken: routeToken)
        }
        .navigationChrome()
    }

    /// Rückgängig-Toast und Sync-Pille als schwebende Schicht — in der
    /// Fallback-Leiste stecken sie im Chrom-Stapel, hier sind sie die ganze
    /// Schicht.
    private var floatingPills: some View {
        VStack(spacing: Theme.Metrics.gap) {
            filterToast
            undoToast
            syncBadge
            saveErrorBadge
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.bottom, Theme.Metrics.gap)
    }

    /// A save that did not land, so the person knows their change is not kept
    /// rather than discovering it next launch.
    ///
    /// A file that would not decode is the more serious of the two: the list
    /// comes up empty and, without this, reads as "everything was deleted". It
    /// says so instead, and points at the copy that was kept.
    @ViewBuilder
    private var saveErrorBadge: some View {
        if store.readFailed {
            Text(String(localized: "Die Datei lies sich nicht einlesen. Eine Kopie liegt als haiity.corrupt.json."))
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .appToastSurface()
                .foregroundStyle(.red)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("save-error-status")
        } else if let message = store.lastWriteError {
            Text(message)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .appToastSurface()
                .foregroundStyle(.red)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("save-error-status")
        }
    }

    /// A filter is a mode, not a one-shot action. Keep the same glass toast
    /// family as undo/sync visible while the mode is active and offer the
    /// reset at the point where the user notices the filtered list.
    @ViewBuilder
    private var filterToast: some View {
        if nativeTab == .habits,
           habitFilter.status != .all || habitFilter.itemType != .all {
            actionToast(label: {
                Label(String(localized: "Filter aktiv"),
                      systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.footnote)
                    .lineLimit(1)
            }, actionTitle: String(localized: "Zurücksetzen"),
                         actionIdentifier: "clear-filters") {
                    withAnimation {
                        habitFilter = HabitListFilter(todayOnly: habitFilter.todayOnly)
                    }
            }
            .transition(reduceMotion ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("filter-toast")
        }
    }

    private var habitsStack: some View {
        NavigationStack {
            habitsScreen
        }
        .navigationChrome()
    }

    // MARK: – Die Anlegen-Seite

    /// Die Anlegen-Seite: dasselbe Formular wie bisher im Half-Sheet
    /// (EditHabitSheet bringt seinen eigenen NavigationStack samt
    /// Sichern-Knopf mit), jetzt als volle Seite mit X oben links
    /// (`asPage`). Ziel der Zoom-Transition: sie wächst aus dem
    /// Anlegen-Knopf und schrumpft dorthin zurück.
    private var createPage: some View {
        EditHabitSheet(store: store, asPage: true)
            .themed(store, palettes: effectivePalettes)
            .environment(\.appearanceBackgroundOwned, false)
            .modifier(MoreZoomDestination(id: Self.createZoomID,
                                          namespace: createZoomNamespace))
    }

    private static let createZoomID = "create-circle"

    /// Der EINE Weg zum Anlegen — alle vier Einstiege laufen hier durch:
    /// Toolbar-+, Leerzustand, Fallback-Chrom und der Deep-Link
    /// `haiity://create`. Ein zweiter Weg zum Cover wäre ein zweiter Weg am
    /// Limit vorbei, und daran hängt der einzige harte Unterschied zwischen
    /// frei und Pro.
    ///
    /// Gegated wird die ABSICHT, nie der Bestand: wer aus dem Archiv
    /// zurückholt, importiert oder über iCloud mehr als drei aktive Habits
    /// bekommt, behält sie und kann sie voll benutzen (siehe ProGate).
    private func requestCreate() {
        showAdd = true
    }

    @ViewBuilder
    private func moreDestination(_ route: MoreRoute) -> some View {
        Group {
            switch route {
            case .archive: ArchiveView(store: store)
            case .about: AboutView(store: store)
            case .github:
                GitHubSettingsView(store: github,
                                   showsUsername: githubUsernameBinding,
                                   showsMonthLabels: githubMonthLabelsBinding)
            case .appearance:
                MoreView(store: store, github: github, cloudStatus: cloudStatus,
                         statsCards: viewPreferences, onOpen: presentMoreSheet,
                         graphShowsMonthLabels: githubMonthLabelsBinding,
                         routeToken: routeToken, screen: .appearance)
            case .habitBehavior:
                MoreView(store: store, github: github, cloudStatus: cloudStatus,
                         statsCards: viewPreferences, onOpen: presentMoreSheet,
                         graphShowsMonthLabels: githubMonthLabelsBinding,
                         routeToken: routeToken, screen: .habitBehavior)
            // Its own branch and its own screen, not a shared one: a child page
            // that inherits its parent's screen identity reuses the parent's view
            // state, so the model page would arrive already scrolled and already
            // holding the previous page's selection.
            case .localModel:
                MoreView(store: store, github: github, cloudStatus: cloudStatus,
                         statsCards: viewPreferences, onOpen: presentMoreSheet,
                         graphShowsMonthLabels: githubMonthLabelsBinding,
                         routeToken: routeToken, screen: .localModel)
            // Check ownership at the destination too, not only at the row that
            // opens it. A stale local flag must never build this page.
            case .developer:
                if DeveloperAccess.isAvailable(storedAppleUserID: PersonalName.appleUserID,
                                               storedAppleEmail: PersonalName.appleEmail) {
                    DeveloperView(store: store, cloudStatus: cloudStatus)
                }
            }
        }
    }

    @ViewBuilder
    private func moreSheetRoot(fallback: MoreRoute) -> some View {
        // The sheet item is the source of truth. Reading a second, delayed
        // destination state let a new Darstellung sheet reuse Verhalten's
        // already-mounted view tree.
        moreDestination(fallback)
            .id("more-destination-\(fallback)")
    }

    // MARK: – Schütteln meldet einen Fehler

    /// Wie lange nach dem Zufahren des Melde-Blatts ein Schütteln nicht zählt.
    ///
    /// Zwei Sekunden sind die Zeit, die eine Hand braucht, um nach dem
    /// Schütteln zur Ruhe zu kommen — und die iOS braucht, um das Blatt
    /// wegzuanimieren. Kürzer, und das eben geschlossene Blatt käme durch das
    /// Nachwippen sofort zurück.
    private static let shakeQuietWindow: TimeInterval = 2

    /// Ein Schütteln — und die drei Gründe, aus denen daraus NICHTS wird.
    ///
    /// **Warum die Prüfungen hier stehen und nicht im Baustein.** `onShake`
    /// meldet nur, DASS geschüttelt wurde (siehe `ShakeDetector`). Ob ein
    /// Blatt aufgehen darf, weiß allein diese Ansicht: ihr gehören alle
    /// Präsentationen.
    ///
    /// **Warum ein offenes Blatt zählt.** iOS präsentiert kein zweites Blatt
    /// über einem, das gerade aufgeht — der Versuch verschluckt es
    /// stillschweigend, und danach steht ein `showFeedback = true`, zu dem es
    /// keine Ansicht gibt. Wer im Kaufblatt schüttelt, bekommt deshalb
    /// nichts; das ist ehrlicher als ein Blatt, das nur manchmal kommt.
    ///
    /// **Warum die Antwort `Bool` ist.** Sie sagt dem Melder, ob die Geste
    /// verbraucht wurde. Nur dann wird sie aus der Antwortkette genommen;
    /// sonst gehört sie wieder iOS und darf dort das Rückgängig-Schütteln
    /// auslösen (siehe `ShakeDetector`).
    @discardableResult
    private func handleShake() -> Bool {
        guard ShakeToReport.isEnabled else { return false }
        guard !isPresentingModally else { return false }
        guard Date.now.timeIntervalSince(feedbackClosedAt) >= Self.shakeQuietWindow else {
            return false
        }
        showFeedback = true
        return true
    }

    /// Steht gerade irgendetwas über der Liste?
    ///
    /// Zwei Quellen, und die zweite ist die wichtigere:
    ///  * Die Zustände DIESER Ansicht — sie stehen schon, bevor iOS überhaupt
    ///    zu präsentieren beginnt, und schliessen das Fenster zwischen „Blatt
    ///    angefordert" und „Blatt liegt oben".
    ///  * `ModalPresentation.isPresenting` — alles ANDERE. Diese Ansicht kennt
    ///    nur ihre eigenen Präsentationen; die Blätter von „Mehr" (Farbe
    ///    anlegen, Umbenennen, Kaufblatt, Dateiwähler), das Kaufblatt der
    ///    Statistik und die Teilen-Blätter der Karten hängen tiefer im Baum.
    ///    Ohne diese Frage setzte ein Schütteln über einem von ihnen ein
    ///    `showFeedback = true`, das iOS verschluckt — und weil `showFeedback`
    ///    danach stehen bliebe, wäre die Geste für den Rest der Sitzung tot.
    private var isPresentingModally: Bool {
        showFeedback || showAdd || showReminderSetup
            || paywall != nil || editing != nil
            || moreSheet != nil || morePageRoute != nil
            || ModalPresentation.isPresenting
    }

    // MARK: – Habits-Bereich

    /// Suche programmatisch öffnen — der EINE Weg für Deep-Links.
    private func openSearch(routeGeneration: Int? = nil) {
        trace("openSearch showAdd=\(showAdd)")
        guard routeWorkIsCurrent(routeGeneration), !showAdd else { return }
        if #available(iOS 26, *) {
            nativeTab = .search
            guard routeWorkIsCurrent(routeGeneration) else { return }
            focusSearchField()
        } else {
            searching = true
        }
    }

    private func routeWorkIsCurrent(_ generation: Int?) -> Bool {
        guard let generation else { return true }
        return routeWork.isCurrent(generation)
    }

    /// Aus dem Such-Tab heraus zu Nacharbeiten: erst zurück zu Habits (dort
    /// wohnen Karte, Vorhang und Anker-Messung), dann öffnen.
    private func redirectBackfillFromSearch(_ habit: Habit, day: String) {
        if #unavailable(iOS 26) { searching = false }
        searchCommitTask?.cancel()
        search = ""
        committedSearch = ""
        nativeTab = .habits
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            openBackfill(habit, day: day, afterMenu: false)
        }
    }

    private var filteredHabits: [Habit] {
        let active = listFilteredHabits
        let q = committedSearch
        guard !q.isEmpty else { return active }
        return active.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.emoji.contains(q)
        }
    }

    /// Search ignores the Habits-tab filter. Hidden or "done today" rows
    /// must still be findable by name.
    private var searchResults: [Habit] {
        let active = visibleActiveHabits
        let q = committedSearch
        guard !q.isEmpty else { return active }
        return active.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.emoji.contains(q)
        }
    }

    private var listFilteredHabits: [Habit] {
        visibleActiveHabits.filter {
            habitFilter.matches($0,
                                 defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                                 now: progressNow)
        }
    }

    @ViewBuilder
    private var habitsScreen: some View {
        if visibleActiveHabits.isEmpty && github.snapshot == nil {
            emptyState
                .navigationBarTitleDisplayMode(.inline)
                .legacySearchDrawer(text: $search,
                                    isPresented: $searching,
                                    prompt: String(localized: "Habits und Erinnerungen durchsuchen"))
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        RootPageCompactTitle(title: String(localized: "Habits"), progress: 1)
                    }
                    createToolbarItem
                }
        } else {
            habitList
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.habitInlineSortingActive, habitSortingActive)
                .legacySearchDrawer(text: $search,
                                    isPresented: $searching,
                                    prompt: String(localized: "Habits und Erinnerungen durchsuchen"))
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        RootPageCompactTitle(title: String(localized: "Habits"),
                                             progress: rootTitleProgress)
                            .allowsHitTesting(sortingDraggedID == nil)
                    }
                    ToolbarItemGroup(placement: .topBarLeading) {
                        if !habitSortingActive {
                            habitFilterMenu
                                .transition(.scale(scale: 0.6, anchor: .leading)
                                    .combined(with: .opacity))
                        }
                        Button {
                            setHabitSortingActive(true)
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .symbolVariant(habitSortingActive ? .fill : .none)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .symbolEffect(.bounce, value: habitSortingActive)
                        .allowsHitTesting(sortingDraggedID == nil)
                        .disabled(!canSortHabits || habitsTabSource.isEmpty)
                        .accessibilityLabel(habitSortingActive
                                            ? String(localized: "Sortieren beenden")
                                            : String(localized: "Habits sortieren"))
                        .accessibilityIdentifier("reorder-habits")
                    }
                    createToolbarItem
                }
        }
    }

    @ToolbarContentBuilder
    private var createToolbarItem: some ToolbarContent {
        if habitSortingActive {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Fertig")) {
                    finishHabitSorting()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .allowsHitTesting(sortingDraggedID == nil)
                .accessibilityIdentifier("finish-reordering")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button { requestCreate() } label: {
                    Image(systemName: "plus")
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .modifier(MoreZoomSource(id: Self.createZoomID,
                                         namespace: createZoomNamespace))
                .accessibilityLabel(CreateAccessibility.label)
                .accessibilityIdentifier(CreateAccessibility.identifier)
            }
        }
    }

    /// Was der HABITS-Tab zeigt. Ab iOS 26 IMMER alles: die Suche wohnt im
    /// eigenen Such-Tab, und ein `search`, das nebenbei auch diese Liste
    /// filtert, hieß: jeder Tastendruck und jedes Leeren baut BEIDE
    /// montierten Listen um — gemessen der halbe „dropping fps"-Ruckler
    /// beim Tippen und Schließen. Nur der Fallback vor iOS 26 (Such-Drawer
    /// AUF der Habit-Liste) filtert hier weiter.
    private var habitsTabSource: [Habit] {
        if #available(iOS 26, *) { return listFilteredHabits }
        return filteredHabits
    }

    private var canSortHabits: Bool {
        committedSearch.isEmpty
            && habitFilter.status == .all
            && habitFilter.itemType == .all
    }

    @ViewBuilder
    private var habitFilterMenu: some View {
        Menu {
            Menu {
                filterStatusButton(.all, title: String(localized: "Alle"))
                filterStatusButton(.done, title: String(localized: "Erledigt"))
                filterStatusButton(.notDone, title: String(localized: "Nicht erledigt"))
            } label: {
                Label(String(localized: "Status"), systemImage: "checkmark.circle")
            }

            Menu {
                filterTypeButton(.all, title: String(localized: "Alle"))
                filterTypeButton(.habit, title: String(localized: "Habit"))
                filterTypeButton(.reminder, title: String(localized: "Erinnerung"))
            } label: {
                Label(String(localized: "Typ"), systemImage: "line.3.horizontal.decrease.circle")
            }

            if habitFilter.status != .all || habitFilter.itemType != .all {
                Button {
                    habitFilter = HabitListFilter(todayOnly: habitFilter.todayOnly)
                } label: {
                    Label(String(localized: "Filter zurücksetzen"), systemImage: "arrow.counterclockwise")
                }
            }

            Divider()
            Button { presentMoreSheet(.archive) } label: {
                Label(String(localized: "Archiv"), systemImage: "archivebox")
            }
            .accessibilityIdentifier("open-archive")
        } label: {
            Label(String(localized: "Filter"),
                  systemImage: habitFilter.isEmpty
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityValue(habitFilter.isEmpty
                            ? String(localized: "Kein Filter aktiv")
                            : String(localized: "Filter aktiv"))
        .accessibilityIdentifier("habit-filter")
    }

    private func filterStatusButton(_ status: HabitListFilter.Status,
                                    title: String) -> some View {
        Button {
            habitFilter.status = status
        } label: {
            filterChoiceLabel(title, selected: habitFilter.status == status)
        }
    }

    private func filterTypeButton(_ type: HabitListFilter.ItemType,
                                  title: String) -> some View {
        Button {
            habitFilter.itemType = type
        } label: {
            filterChoiceLabel(title, selected: habitFilter.itemType == type)
        }
    }

    private func filterChoiceLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: Theme.Metrics.gap)
            if selected { Image(systemName: "checkmark") }
        }
    }

    private var habitList: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    RootPageTitle(title: String(localized: "Habits"),
                                  subtitle: String(localized: "Dein Rhythmus in einem Blick"))
                        .id("habit-list-title")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .moveDisabled(true)
                        .allowsHitTesting(!habitSortingActive)
                    TodayProgressView(
                        progress: ScheduledProgress.today(habits: visibleActiveTrackedHabits,
                            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier, now: progressNow),
                        todayOnly: $habitFilter.todayOnly)
                        .id("habit-list-top")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Metrics.gutter,
                                                  bottom: 0, trailing: Theme.Metrics.gutter))
                        .moveDisabled(true)
                        .allowsHitTesting(!habitSortingActive)
                    if let snapshot = github.snapshot {
                        GitHubContributionCard(snapshot: snapshot,
                                               collapsed: collapsed,
                                               showsUsername: store.githubShowsUsername,
                                               showsMonthLabels: graphShowsMonthLabels,
                                               openProfile: { GitHubLink.open(snapshot.profileURL) })
                            .equatable()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0,
                                                      leading: Theme.Metrics.gutter,
                                                      bottom: 0,
                                                      trailing: Theme.Metrics.gutter))
                            .moveDisabled(true)
                            .allowsHitTesting(!habitSortingActive)
                    }
                    if habitsTabSource.isEmpty {
                        if !habitFilter.isEmpty && committedSearch.isEmpty {
                            ContentUnavailableView(String(localized: "Keine passenden Einträge"),
                                systemImage: "checkmark.circle",
                                description: Text(String(localized: "Ändere die Filter, um weitere Einträge zu sehen.")))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else if github.snapshot == nil || !search.isEmpty {
                            ContentUnavailableView.search(text: search)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                if !habitsTabSource.isEmpty {
                    Section {
                        ForEach(habitsTabSource) { habit in
                            row(for: habit)
                                .id(rowIdentity(habit))
                                .opacity(sortingDraggedID == habit.id ? 0 : 1)
                                .animation(nil, value: sortingDraggedID)
                                .deleteDisabled(true)
                        }
                    }
                }
            }
            .accessibilityIdentifier(habitSortingActive ? "habit-sorting-active" : "habit-list")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { scrollToRequestedHabit(using: proxy) }
            .onChange(of: requestedHabitID) { _, _ in
                scrollToRequestedHabit(using: proxy)
            }
            .onChange(of: habitsTabSource.map(\.id)) { _, _ in
                guard !habitSortingActive else { return }
                scrollToRequestedHabit(using: proxy)
            }
        }
        .listStyle(.plain)
        .background {
            HabitSortingSession(
                active: habitSortingActive,
                habitIDs: habitsTabSource.map(\.id),
                move: reorderHabit,
                persist: { store.persist() },
                onDraggingIDChange: { id in
                    sortingDraggedID = id
                })
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            progressNow = now
        }
        .onChange(of: habitSortingActive) { _, active in
            guard active else {
                sortingDraggedID = nil
                store.persist()
                return
            }
            NotificationCenter.default.post(name: .swipeRevealDismissAll, object: nil)
        }
        // Das Chrom liegt ÜBER der Liste. Ohne diese Boden-Marge endet der
        // scrollbare Inhalt genau darunter — auf schmalen Geräten und in den
        // Accessibility-Größen verdeckt es dann dauerhaft das Raster der
        // letzten Karte, und zwar in RTL genauso.
        // The speak button floats above the tab bar, so the list needs margin
        // for it as well as for the bar. Without this the last habit's title ends
        // up behind the button instead of above it.
        .contentMargins(.bottom, speakButtonFootprint, for: .scrollContent)
        // Karten sind weiß/#1C1C1E, die Seite muss also die gruppierte
        // Fläche sein. Kein toolbarBackground-Override — die Navigations-
        // leiste behält ihr System-Glas.
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.bottom, Theme.Metrics.gap, for: .scrollContent)
        .softScrollEdges()
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

    /// Fußabdruck des Chroms: Knopfhöhe + Abstand zur Unterkante + Luft. Der
    /// Wert ist ABSICHTLICH unabhängig vom Zusammenziehen — würde die Marge
    /// mitschrumpfen, verschöbe sich der Inhalt, das Scroll-Signal bekäme
    /// eine Bewegung ohne Finger und der Umschalter triebe sich selbst.
    /// Extra room below the habit list for the shell's speak button.
    ///
    /// On iOS 26 and later the native bar supplies its own inset, so
    /// `chromeFootprint` is deliberately zero — which leaves nothing accounting
    /// for a control that floats ABOVE that bar.
    private var speakButtonFootprint: CGFloat {
        chromeFootprint + ChromeLayout.speakButtonTop + 8
    }

    private var chromeFootprint: CGFloat {
        // Ab iOS 26 stellt die NATIVE Leiste ihre eigene Sicherheitszone —
        // die Liste endet automatisch über ihr, eine zusätzliche Marge wäre
        // ein leerer Streifen.
        if #available(iOS 26, *) { return 0 }
        return Theme.Metrics.control + Theme.Metrics.gap + Theme.Metrics.gutter
    }

    private func habitCalendar(for habit: Habit) -> Calendar {
        HabitTimeZone.calendar(for: habit,
                               defaultIdentifier: store.defaultTimeZoneIdentifier)
    }

    private func scrollToRequestedHabit(using proxy: ScrollViewProxy) {
        guard let id = requestedHabitID,
              habitsTabSource.contains(where: { $0.id == id }) else { return }
        Task { @MainActor in
            for attempt in 0..<6 {
                guard requestedHabitID == id else { return }
                if attempt > 0 {
                    try? await Task.sleep(for: .milliseconds(80))
                }
                await Task.yield()
                guard requestedHabitID == id else { return }
                if reduceMotion {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            if requestedHabitID == id {
                requestedHabitID = nil
            }
        }
    }

    private func habitToday(_ habit: Habit) -> String {
        DayKey.today(calendar: habitCalendar(for: habit))
    }

    private func rowIdentity(_ habit: Habit) -> String {
        // Keep gesture state alive while a reminder's completion and cursor
        // change. Re-keying on either value replaces the row mid-touch and
        // can expose the checkmark to the same tap as a reveal action.
        return habit.id.uuidString
    }

    private func enableSorting() {
        setHabitSortingActive(true)
    }

    private func finishHabitSorting() {
        setHabitSortingActive(false)
        store.persist()
    }

    private func setHabitSortingActive(_ active: Bool) {
        guard habitSortingActive != active else { return }
        withHabitChromeAnimation { habitSortingActive = active }
    }

    private func reorderHabit(from source: IndexSet, to destination: Int, persist: Bool) {
        let visibleIDs = habitsTabSource.map(\.id)
        if reduceMotion {
            store.moveVisible(visibleIDs,
                              fromOffsets: source,
                              toOffset: destination,
                              persist: persist)
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                store.moveVisible(visibleIDs,
                                  fromOffsets: source,
                                  toOffset: destination,
                                  persist: persist)
            }
        }
    }

    private func createOneTime(from habit: Habit) {
        guard habit.recurrence.frequency != .once else { return }
        let calendar = habitCalendar(for: habit)
        let today = DayKey.today(calendar: calendar)
        let day = habit.recurrence.schedule(calendar: calendar).first(onOrAfter: today) ?? today
        store.add(habit.oneTimeCopy(on: day), after: habit.id)
    }

    // Die Statistik-Karten über dem Titel sind in den eigenen
    // Statistik-Tab umgezogen (siehe StatsView) — die Habit-Liste beginnt
    // wieder mit ihrem Titel.

    @ViewBuilder
    private func searchRow(for habit: Habit) -> some View {
        let reveal = revealActions(for: habit)
        SearchResultRow(habit: habit,
                        onEdit: { editing = habit },
                        onToggleReminder: { toggleReminder(habit) },
                        calendar: habitCalendar(for: habit),
                        leadingSwipe: reveal.leading,
                        trailingSwipe: reveal.trailing)
            .equatable()
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                      leading: Theme.Metrics.gutter,
                                      bottom: Theme.Metrics.gap,
                                      trailing: Theme.Metrics.gutter))
    }

    @ViewBuilder
    private func row(for habit: Habit, inSearchTab: Bool = false) -> some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("row")
        #endif
        switch ItemPresentation.forItem(habit) {
        case .reminderRow:
            let reveal = revealActions(for: habit)
            ReminderRow(habit: habit,
                        onToggle: { toggleReminder(habit) },
                        onEdit: { editing = habit },
                        onArchive: { store.archive(habit.id) },
                        onRevert: { revertReminder(habit) },
                        onDelete: { pendingDelete = habit },
                        onCreateOneTime: { createOneTime(from: habit) },
                        onEnableSorting: enableSorting,
                        calendar: habitCalendar(for: habit),
                        leadingSwipe: reveal.leading,
                        trailingSwipe: reveal.trailing)
                .equatable()
                // Keep the row identity stable. The reminder's value and
                // cursor are ordinary inputs, so SwiftUI updates the button
                // state without leaving XCTest/VoiceOver with a stale node.
                .id("reminder-row-\(habit.id.uuidString)")
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0,
                                          leading: Theme.Metrics.gutter,
                                          bottom: Theme.Metrics.gap,
                                          trailing: Theme.Metrics.gutter))
        case .habitCard:
            let reveal = revealActions(for: habit)
            HabitCard(
                habit: habit,
                collapsed: collapsed,
                showsMonthLabels: graphShowsMonthLabels,
                onToggleDay: { toggleDay(habit, day: $0) },
                onBackfill: {
                    if inSearchTab { redirectBackfillFromSearch(habit, day: habitToday(habit)) }
                    else { openBackfill(habit, day: habitToday(habit), afterMenu: true) }
                },
                onIncrement: { increment(habit) },
                onClear: { revert(habit) },
                onMarkDone: { markDone(habit) },
                onEdit: { editing = habit },
                onArchive: { store.archive(habit.id) },
                onDelete: { pendingDelete = habit },
                onCreateOneTime: { createOneTime(from: habit) },
                onEnableSorting: enableSorting,
                onAnswer: { answer(habit, yes: $0) },
                leadingSwipe: reveal.leading,
                trailingSwipe: reveal.trailing,
                calendar: habitCalendar(for: habit))
                .equatable()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0,
                                          leading: Theme.Metrics.gutter,
                                          bottom: 0,
                                          trailing: Theme.Metrics.gutter))
        }
    }

    /// Die Wisch-Aktionen als KARTENHOHE eigene Knöpfe (siehe SwipeReveal in
    /// HabitCard) statt `.swipeActions`: die System-Knöpfe sind auf hohen
    /// Zeilen fixe Kapseln (nachgemessen, nicht beeinflussbar) — neben einer
    /// Rasterkarte wirkten sie verloren, und über dem Raster feuerte der
    /// System-Wischer gar nicht erst (die horizontale ScrollView gewann).
    /// Erste Aktion je Seite bleibt die FESTE, artgerechte; die Extras aus
    /// den Einstellungen folgen dahinter.
    private func revealActions(for habit: Habit) -> (leading: [RevealAction], trailing: [RevealAction]) {
        let swipes = viewPreferences.preferences.effectiveSwipeActions(for: habit)
        var leading = [revealAction(primarySwipe(for: habit), habit: habit)]
        if let extra = swipes.leading { leading.append(revealAction(extra, habit: habit)) }
        var trailing = [revealAction(secondarySwipe(for: habit), habit: habit)]
        if let extra = swipes.trailing { trailing.append(revealAction(extra, habit: habit)) }
        return (leading, trailing)
    }

    private func revealAction(_ action: EffectiveSwipeAction, habit: Habit) -> RevealAction {
        let label = swipeLabel(action.operation)
        return RevealAction(operation: action.operation,
                            title: label.title,
                            symbol: label.symbol,
                            tint: label.tint) { perform(action.operation, on: habit) }
    }

    private func primarySwipe(for habit: Habit) -> EffectiveSwipeAction {
        switch habit.kind {
        case .checkbox: return EffectiveSwipeAction(operation: .done)
        case .quantity: return EffectiveSwipeAction(operation: .increment)
        case .yesNo: return EffectiveSwipeAction(operation: .yes)
        }
    }

    private func secondarySwipe(for habit: Habit) -> EffectiveSwipeAction {
        EffectiveSwipeAction(operation: habit.kind == .yesNo ? .no : .reset)
    }

    private func perform(_ operation: SwipeOperation, on habit: Habit) {
        if habit.isReminder {
            switch operation {
            case .done: requestReminderCompletion(habit)
            case .reset: revertReminder(habit)
            case .archive: store.archive(habit.id)
            case .backfill: openBackfill(habit, day: habitToday(habit), afterMenu: false)
            case .session: HabitSessionManager.shared.start(habit: habit)
            case .edit: editing = habit
            case .increment, .yes, .no: break
            }
            return
        }
        switch operation {
        case .done: markDone(habit)
        case .reset: revert(habit)
        case .increment: increment(habit)
        case .yes: answer(habit, yes: true)
        case .no: answer(habit, yes: false)
        case .archive: store.archive(habit.id)
        case .backfill: openBackfill(habit, day: habitToday(habit), afterMenu: false)
        case .session: HabitSessionManager.shared.start(habit: habit)
        case .edit: editing = habit
        }
    }

    private func handleNotificationAction(_ request: NotificationActionRequest) {
        guard let habit = visibleActiveHabits.first(where: { $0.id == request.target.habitID }) else { return }
        switch request.action {
        case .backfill:
            openBackfill(habit, day: request.target.day, afterMenu: false)
        case .session:
            HabitSessionManager.shared.start(habit: habit)
        case .edit:
            editing = habit
        default:
            break
        }
    }

    private func handlePendingNotificationAction() {
        guard let request = NotificationActionRouter.takePending() else { return }
        handleNotificationAction(request)
    }

    private func handlePendingNotificationDeliveryIssue() {
        let delivered = NotificationDeliveryIssueCenter.deliverPendingMessage { message in
            Task { @MainActor in
                await flash(message)
            }
        }
        guard delivered else { return }
    }

    private func schedulePendingNotificationAction() {
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else { return }
            handlePendingNotificationAction()
        }
    }

    private func schedulePendingNotificationDeliveryIssue() {
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else { return }
            handlePendingNotificationDeliveryIssue()
        }
    }

    /// Dieselbe Geduld wie beim Benachrichtigungs-Router: die Schnellaktion
    /// parkt früh, aber erst ein aktives Fenster darf umschalten. Ein
    /// verpasster Anruf bleibt geparkt, bis der nächste Aktiv-Wechsel holt.
    private func schedulePendingShortcutLink() {
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else { return }
            guard let url = HomeShortcuts.takePending() else { return }
            handleDeepLink(url)
        }
    }

    private func swipeLabel(_ operation: SwipeOperation)
        -> (title: String, symbol: String, tint: Color) {
        switch operation {
        case .done: return (String(localized: "Erledigt"), "checkmark", .green)
        case .reset: return (String(localized: "Zurücksetzen"), "arrow.uturn.backward", .gray)
        case .increment: return (String(localized: "+1"), "plus", .green)
        case .yes: return (String(localized: "Ja"), "checkmark", .green)
        case .no: return (String(localized: "Nein"), "xmark", .red)
        case .archive: return (String(localized: "Archivieren"), "archivebox", .orange)
        case .backfill: return (String(localized: "Nacharbeiten"), "calendar.badge.plus", .indigo)
        case .session: return (String(localized: "Session starten"), "timer", .teal)
        case .edit: return (String(localized: "Bearbeiten"), "pencil", .blue)
        }
    }

    // MARK: – Check-in mit Rückgängig
    //
    // ALLES, was aus der OBERFLÄCHE einen Tageswert ändert, läuft durch
    // `mutate`: erst den alten Wert merken, dann ändern, dann den Toast
    // zeigen. Der Widget-Knopf und Siri/Shortcuts (CheckOffLogic im
    // Extension- bzw. Intent-Prozess) laufen BEWUSST NICHT hier durch — ein
    // Toast ist Oberfläche, und dort gibt es keine, die ihn zeigen könnte.

    private func mutate(_ habit: Habit, day: String, _ change: () -> Void) {
        let before = store.value(habit.id, day: day)
        change()
        let after = store.value(habit.id, day: day) ?? 0
        let message = CheckInUndo.message(habit: habit, value: after, day: day)
        withToastAnimation {
            undo.present(habitId: habit.id, day: day, previousValue: before, message: message)
        }
    }

    /// Tippen auf die Heute-Pille bzw. auf eine Rasterzelle: schaltet um.
    private func toggleDay(_ habit: Habit, day: String) {
        mutate(habit, day: day) { store.toggle(habit.id, day: day) }
    }

    private func increment(_ habit: Habit) {
        let today = habitToday(habit)
        mutate(habit, day: today) { store.increment(habit.id, day: today) }
    }

    /// Heute beantworten (Habit-Art „Ja/Nein"). Läuft durch dieselbe Stelle
    /// wie jedes Abhaken — also mit exaktem Rückgängig, auch wenn die
    /// Antwort eine bestehende überschreibt.
    private func answer(_ habit: Habit, yes: Bool) {
        let today = habitToday(habit)
        mutate(habit, day: today) { store.answer(habit.id, day: today, yes: yes) }
    }

    /// Wisch-„Erledigt": hakt AN, nie ab. Ein schon erledigtes Checkbox-
    /// Habit bleibt unangetastet (und bekommt keinen Toast, der nichts
    /// zurückzunehmen hätte) — zum Abhaken gibt es „Rückgängig".
    private func markDone(_ habit: Habit) {
        let today = habitToday(habit)
        // `isDone` ist bei Ja/Nein die ANTWORT und nicht „es steht ein Wert
        // da" — ein verneinter Tag ist hier also offen und darf auf Ja
        // gedreht werden.
        if habit.kind != .quantity, habit.isDone(today) { return }
        mutate(habit, day: today) {
            switch habit.kind {
            case .quantity: store.increment(habit.id, day: today)
            case .yesNo:    store.setValue(habit.id, day: today, value: Habit.Answer.yes)
            case .checkbox: store.toggle(habit.id, day: today)
            }
        }
    }

    /// Heutigen Eintrag zurücknehmen — komplett, auch bei Mengen-Habits.
    /// Der Toast bringt den exakten Vorwert zurück.
    private func revert(_ habit: Habit) {
        let today = habitToday(habit)
        guard store.value(habit.id, day: today) != nil else { return }
        mutate(habit, day: today) { store.clear(habit.id, day: today) }
    }

    private func toggleReminder(_ reminder: Habit) {
        let calendar = habitCalendar(for: reminder)
        let state = ReminderOccurrenceEngine.state(for: reminder, calendar: calendar)
        if state.isChecked(calendar: calendar) {
            revertReminder(reminder)
        } else {
            requestReminderCompletion(reminder)
        }
    }

    private func requestReminderCompletion(_ reminder: Habit) {
        let current = store.habits.first(where: { $0.id == reminder.id }) ?? reminder
        let calendar = habitCalendar(for: current)
        let state = ReminderOccurrenceEngine.state(for: current, calendar: calendar)
        guard let occurrence = state.actionable else { return }
        if occurrence.dueDate > .now {
            earlyReminderCompletion = PendingReminderCompletion(habitID: current.id,
                                                                day: occurrence.day)
        } else {
            completeReminder(current, occurrence: occurrence)
        }
    }

    private func confirmEarlyReminderCompletion() {
        guard let pending = earlyReminderCompletion,
              let reminder = visibleActiveHabits.first(where: { $0.id == pending.habitID }),
              let due = ReminderOccurrenceEngine.dueDate(
                day: pending.day,
                reminder: reminder,
                calendar: habitCalendar(for: reminder))
        else {
            earlyReminderCompletion = nil
            return
        }
        earlyReminderCompletion = nil
        completeReminder(reminder,
                         occurrence: ReminderOccurrence(day: pending.day, dueDate: due))
    }

    private func completeReminder(_ reminder: Habit, occurrence: ReminderOccurrence) {
        let current = store.habits.first(where: { $0.id == reminder.id }) ?? reminder
        let calendar = habitCalendar(for: current)
        let cursor = current.repeatsWhileIncomplete ? nil
            : ReminderOccurrenceEngine.cursorAfterCompleting(occurrence,
                                                             reminder: current,
                                                             calendar: calendar)
        store.setReminderCompletion(current.id, day: occurrence.day,
                                    completed: true, nextCursor: cursor)
        Theme.Haptics.check()
    }

    private func revertReminder(_ reminder: Habit) {
        let current = store.habits.first(where: { $0.id == reminder.id }) ?? reminder
        let calendar = habitCalendar(for: current)
        let state = ReminderOccurrenceEngine.state(for: current, calendar: calendar)
        // Prefer the persisted completion. The occurrence projection can
        // briefly lag while a reminder row is re-keyed after completion, but
        // the log is already the source of truth for the action.
        let completedDay = current.log.keys
            .filter { current.recurrence.schedule(calendar: calendar).isScheduled($0) }
            .sorted()
            .last ?? state.mostRecentCompleted?.day
        guard let completedDay else { return }
        store.setReminderCompletion(current.id, day: completedDay,
                                    completed: false, nextCursor: nil)
        Theme.Haptics.select()
    }

    /// Rückgängig nimmt den GANZEN Vorgang zurück — jeden Tag auf genau den
    /// Wert, den er vorher hatte.
    private func performUndo() {
        guard let toast = undo.take() else { return }
        for entry in toast.entries {
            store.setValue(toast.habitId, day: entry.day, value: entry.previousValue)
        }
        Theme.Haptics.check()
    }

    // MARK: – Nacharbeiten

    /// Welche Karte offen ist. Der Tag steckt MIT drin (und ist
    /// veränderlich), das Habit nur als Kennung — siehe `backfill`.
    struct BackfillRequest: Identifiable, Equatable {
        let habitId: UUID
        var day: String
        /// Wo die Karte herkommt: die Lage der Habit-Zeile beim Öffnen, als
        /// Anker der Skalierung (0…1 der Bildschirmhöhe). Einmal beim Öffnen
        /// bestimmt und dann FEST — die Karte schrumpft beim Schließen an
        /// dieselbe Stelle zurück, auch wenn die Liste inzwischen anders
        /// stünde.
        var anchor: UnitPoint = .center

        var id: UUID { habitId }
    }

    /// Karte öffnen.
    ///
    /// `afterMenu` ist kein Feinschliff: eine Aktion IM Kontextmenü kann
    /// nicht selbst etwas präsentieren — das Menü baut sich beim Antippen
    /// erst ab, und was in derselben Runde erscheint, geht mit ihm unter
    /// (bzw. flackert). Also erst das Menü schließen lassen, dann öffnen. Ein
    /// Zellentipp hat dieses Problem nicht und wartet deshalb auch nicht.
    private func openBackfill(_ habit: Habit, day: String, afterMenu: Bool) {
        let request = BackfillRequest(habitId: habit.id, day: day)
        guard afterMenu else {
            withCardAnimation { backfill = request }
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            withCardAnimation { backfill = request }
        }
    }

    /// Der EINZIGE Schreibweg der Karte — für einen Tag wie für fünfzig.
    ///
    /// Drei Dinge stehen hier bewusst zusammen:
    ///  * **Der Torwächter.** `setValue` prüft seinen Schlüssel nicht (es ist
    ///    der exakte Setter für „Rückgängig"). Jeder Tag geht deshalb durch
    ///    `Backfill.canWrite`, auch der fünfzigste.
    ///  * **EIN Zurück.** Die Vorwerte ALLER betroffenen Tage werden vorher
    ///    eingesammelt und wandern in EINEN Toast. Sieben Toasts wären eine
    ///    Warteschlange, und ein Zurück nur für den letzten Tag ließe sechs
    ///    stille Änderungen stehen.
    ///  * **Einheitlich.** Alle Tage bekommen DENSELBEN Wert. Was gemischt
    ///    war, ist danach gleich — das ist die Zusage der Mehrfachauswahl.
    private func backfillWrite(_ habitId: UUID, days: [String], value: Int?) {
        guard let habit = visibleActiveHabits.first(where: { $0.id == habitId }) else { return }
        let calendar = habitCalendar(for: habit)
        let today = DayKey.today(calendar: calendar)
        let allowed = days.filter {
            Backfill.canWrite(habit: habit, day: $0, today: today, calendar: calendar)
        }.sorted()
        guard !allowed.isEmpty else { return }

        let entries = allowed.map {
            CheckInUndo.Entry(day: $0, previousValue: store.value(habitId, day: $0))
        }
        for day in allowed { store.setValue(habitId, day: day, value: value) }

        let message: String
        if let single = allowed.first, allowed.count == 1 {
            message = CheckInUndo.message(habit: habit,
                                          value: store.value(habitId, day: single) ?? 0,
                                          day: single)
        } else {
            message = CheckInUndo.message(habit: habit,
                                          days: allowed.count,
                                          cleared: value == nil)
        }
        withToastAnimation {
            undo.present(habitId: habitId, entries: entries, message: message)
        }
        Theme.Haptics.check()
    }

    /// Der Rückbau-Weg des Malen-Modus: ABGEWÄHLTE Tage bekommen ihren
    /// EXAKTEN Vorwert zurück (je Tag ein eigener — deshalb reicht `onWrite`
    /// mit seinem einen Wert hier nicht). Sonst dieselben drei Zusagen wie
    /// `backfillWrite`: Torwächter vor jedem Tag, EIN Toast für den ganzen
    /// Griff, und der Toast trägt die Vorwerte, macht also auch DAS wieder
    /// rückgängig.
    private func backfillRestore(_ habitId: UUID,
                                 entries: [(day: String, value: Int?)]) {
        guard let habit = visibleActiveHabits.first(where: { $0.id == habitId }) else { return }
        let calendar = habitCalendar(for: habit)
        let today = DayKey.today(calendar: calendar)
        let allowed = entries.filter {
            Backfill.canWrite(habit: habit, day: $0.day, today: today, calendar: calendar)
        }
            .sorted { $0.day < $1.day }
        guard !allowed.isEmpty else { return }

        let undoEntries = allowed.map {
            CheckInUndo.Entry(day: $0.day, previousValue: store.value(habitId, day: $0.day))
        }
        for entry in allowed { store.setValue(habitId, day: entry.day, value: entry.value) }

        let message: String
        if let single = allowed.first, allowed.count == 1 {
            message = CheckInUndo.message(habit: habit,
                                          value: store.value(habitId, day: single.day) ?? 0,
                                          day: single.day)
        } else {
            message = CheckInUndo.message(habit: habit,
                                          days: allowed.count, cleared: true)
        }
        withToastAnimation {
            undo.present(habitId: habitId, entries: undoEntries, message: message)
        }
        Theme.Haptics.select()
    }

    /// Öffnen/Schließen der Nacharbeiten-Karte: eine Feder mit kurzem,
    /// weichem Ausklang statt der reinen Blendkurve — die Karte SETZT sich,
    /// statt einfach dazustehen. Bei Reduzierter Bewegung bleibt eine reine
    /// Blende (die Karte trägt dann auch nur einen Opacity-Übergang).
    private func withCardAnimation(_ body: () -> Void) {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2), body)
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82), body)
        }
    }

    /// Die Karte, wenn eine offen ist. Sie zieht ihr Habit LIVE aus dem Store
    /// — ist es inzwischen weg (archiviert, gelöscht, Import), schließt sie
    /// sich von selbst, statt einen Stand von vorhin zu zeigen.
    @ViewBuilder
    private func backfillEditor(_ request: BackfillRequest) -> some View {
        if let habit = visibleActiveHabits.first(where: { $0.id == request.habitId }) {
            BackfillCard(habit: habit,
                         day: Binding(get: { backfill?.day ?? request.day },
                                      set: { backfill?.day = $0 }),
                         onWrite: { days, value in
                             backfillWrite(request.habitId, days: days, value: value)
                         },
                         onRestore: { entries in
                             backfillRestore(request.habitId, entries: entries)
                         },
                         onClose: { withCardAnimation { backfill = nil } },
                         sourceAnchor: request.anchor)
                .environment(\.calendar, habitCalendar(for: habit))
                // KEIN eigener Übergang mehr an der ganzen Schicht: Vorhang
                // und Karte tragen ihre Übergänge selbst (BackfillCard.body)
                // — der Vorhang blendet nur, die Karte wächst aus ihrer
                // Zeile. Ein Übergang HIER würde beide zusammen skalieren,
                // und ein skalierender Vorhang war genau das „schlechte
                // Fade" aus der Rückmeldung.
        }
    }

    private func withToastAnimation(_ body: () -> Void) {
        if reduceMotion { body() } else { withAnimation(.snappy(duration: 0.24), body) }
    }

    /// Header-Knöpfe beim Sortieren: Filter und Plus weichen, Fertig kommt,
    /// und die bleibenden Sitze rutschen mit. Dieselbe Feder wie die
    /// Nacharbeiten-Karte — kurz genug für Chrom, weich genug, dass die
    /// Glaskapseln nicht springen. Reduzierte Bewegung lässt sie stehen.
    private func withHabitChromeAnimation(_ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82), body)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DemoGrid(palette: effectivePaletteStyle)
            Text(String(localized: "Noch keine Habits"))
                .font(.title3.bold())
            Text(String(localized: "Lege deinen ersten Eintrag an und hake ihn ab, damit dein Raster sichtbar wächst."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                requestCreate()
            } label: {
                Text(String(localized: "Ersten Habit anlegen"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accentFill(effectivePaletteStyle), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-first-habit")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Fallback-Chrom unten (iOS < 26): Navigation links, + rechts

    @ViewBuilder
    private var legacyBottomChrome: some View {
        // Bei offener Suche steht das Chrom sonst auf der Tastatur. Der
        // Toast hängt bewusst MIT drin: er soll über dem Glas-Blob schweben,
        // nicht darauf — und auf der Tastatur hätte er nichts verloren.
        if #unavailable(iOS 26), !searching {
            VStack(spacing: Theme.Metrics.gap) {
                undoToast
                syncBadge
                chromeGlass
                    // Offene Nacharbeiten-Karte = modal. Der Vorhang der
                    // Karte liegt UNTER dem Chrom (damit der Toast darüber
                    // bleibt), also muss die Leiste selbst stillgelegt
                    // werden — sonst legt ein Fehlgriff auf den + ein Habit
                    // hinter der offenen Karte an. Der Toast steht bewusst
                    // NICHT in dieser Klammer: er ist das Zurück zu genau
                    // dem, was die Karte gerade geschrieben hat.
                    .allowsHitTesting(backfill == nil)
            }
            // Gleicher Seitenrand links wie rechts — der Umschalter steht
            // exakt so weit von der Kante wie der Anlegen-Knopf.
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, Theme.Metrics.gap)
        }
    }

    /// EIN Behälter für alle Glasteile unten. Ohne ihn rechnet jedes Stück
    /// sein Glas für sich und sie bleiben getrennte Scheiben; erst im
    /// Container fließen zwei Formen, die näher beieinanderstehen als
    /// `spacing`, zu EINER Fläche zusammen. Genau das ist „zu einem kleinen
    /// Blob zusammenziehen" (der + wandert in die Kapsel) UND „aus der
    /// Leiste wachsen" (die Tafel hängt an der Kapsel).
    @ViewBuilder
    private var chromeGlass: some View {
        // Die Fallback-Leiste existiert nur unter iOS 26 — dort gibt es kein
        // Liquid Glass und keinen GlassEffectContainer; ChromeGlass fällt
        // intern ohnehin auf die Material-Attrappe zurück.
        chromeStack
    }

    /// EINE Grundlinie: alle Kinder sind `Metrics.control` hoch, damit sitzen
    /// Ober- UND Unterkante von Umschalter und Anlegen-Knopf auf demselben
    /// Strich — unabhängig davon, ob der Knopf gerade rechts in der Ecke oder
    /// links am Blob klebt.
    ///
    /// **Warum der Knopf im Overlay liegt und nicht im HStack.** Vorher stand
    /// er in ZWEI Zweigen (`if collapsed` … `if !collapsed`). Für SwiftUI
    /// sind das zwei verschiedene Views: der eine wird entfernt, der andere
    /// eingesetzt — also eine Blende, egal wie viel Glas-Kennung daran
    /// hängt. Jetzt gibt es genau EINEN Knopf mit EINER Identität, dessen
    /// x-Versatz zwischen beiden Zielen INTERPOLIERT (siehe ChromeLayout).
    /// Er fährt damit sichtbar in den Blob, statt an der einen Stelle
    /// auszublenden und an der anderen aufzublitzen.
    private var chromeStack: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 0) {
                switcher
                Spacer(minLength: 0)
            }
            .frame(height: Theme.Metrics.control)
            .overlay(alignment: .leading) {
                addButton
                    .offset(x: ChromeLayout.addButtonX(collapsed: collapsed,
                                                       rowWidth: geo.size.width))
            }
        }
        .frame(height: Theme.Metrics.control)
    }

    /// Linksbündige Glas-Kapsel für die zwei Inhalte des Fallbacks.
    ///
    /// **Konzentrik.** Die Auswahl-Lasur liegt IN der Kapsel, also ist ihr
    /// Radius exakt der äußere MINUS dem Rand:
    ///
    ///     äußere Kapsel  H = control = 52  ->  R = H/2 = 26
    ///     Rand           p = (control − hit)/2 = 4   (rundum gleich)
    ///     innere Kapsel  h = control − 2p = hit = 44  ->  r = h/2 = 22
    private var switcher: some View {
        HStack(spacing: Self.chromeInset) {
            statsPill
            habitsPill
            morePill
        }
            // RUNDUM derselbe Rand — links wie rechts wie oben wie unten.
            .padding(Self.chromeInset)
            .modifier(ChromeGlass(id: "chrome-nav", namespace: glassNamespace, kind: .capsule,
                                  union: chromeUnion("chrome-nav-solo")))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen-switcher")
    }

    /// Der eine Rand, aus dem beide Radien folgen: (52 − 44)/2 = 4.
    private static let chromeInset: CGFloat = ChromeLayout.inset

    /// Ein Symbol im Chrom. Gleiches Kästchen, damit die Mittelpunkte auf
    /// EINER Linie sitzen — die Punktgrößen sind OPTISCH abgeglichen und
    /// nicht gleich (am Bildschirm nachjustiert).
    private func glyph(_ symbol: String) -> some View {
        let size: CGFloat
        switch symbol {
        case "square.grid.2x2": size = 15   // kompaktes, fettes Zeichen
        case "plus":            size = 17   // wirkt bei gleicher Größe zu groß
        default:                size = 17
        }
        return Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: Theme.Metrics.glyph, height: Theme.Metrics.glyph)
    }

    /// Statistik im Fallback bewusst NUR als Symbol: drei beschriftete
    /// Pillen plus Anlegen-Knopf passen auf 320-pt-Geräte nicht mehr in
    /// eine Zeile, und das Balken-Symbol ist eindeutig.
    private var statsPill: some View {
        navigationPill(tab: .stats, title: "Statistik", symbol: "chart.bar",
                       identifier: "tab-stats", iconOnly: true)
    }

    private var habitsPill: some View {
        navigationPill(tab: .habits, title: "Habits", symbol: "square.grid.2x2",
                       identifier: "tab-habits")
    }

    private var morePill: some View {
        navigationPill(tab: .more, title: "Mehr", symbol: "ellipsis",
                       identifier: "tab-more")
    }

    private func navigationPill(tab: AppTab, title: LocalizedStringKey,
                                symbol: String, identifier: String,
                                iconOnly: Bool = false) -> some View {
        let selected = nativeTab == tab
        return Button {
            nativeTab = tab
        } label: {
            HStack(spacing: 4) {
                glyph(symbol)
                if !collapsed, !iconOnly {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .fixedSize()
                }
            }
            .padding(.horizontal, collapsed ? 0 : Theme.Metrics.gap)
            // Die Lasur IST die Fläche: `hit` hoch UND mindestens `hit` breit.
            .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
            .background {
                if selected {
                    Capsule().fill(Theme.accent(effectivePaletteStyle).opacity(0.18))
                }
            }
            .foregroundStyle(selected
                             ? AnyShapeStyle(Theme.accentText(effectivePaletteStyle))
                             : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }

    /// Der Anlegen-Knopf. EIN Knopf, EINE Größe (`Metrics.control`, dasselbe
    /// Maß wie die Höhe des Umschalters) — er wechselt beim Scrollen nur den
    /// Platz: rechts unten in der Ecke, zusammengezogen direkt links an der
    /// Kapsel. Beide Zustände tragen dieselbe `glassEffectID`, deshalb
    /// WANDERT ein Glasstück und fließt mit dem Umschalter zusammen, statt
    /// dass zwei verschieden große Knöpfe gegeneinander blenden.
    private var addButton: some View {
        Button {
            requestCreate()
        } label: {
            glyph("plus")
                // Aufgenommen im gemeinsamen Blob gibt es keine eingefärbte
                // Scheibe mehr, auf der Weiß stünde — dort trägt das Zeichen
                // selbst die Markenfarbe.
                .foregroundStyle(collapsed
                                 ? AnyShapeStyle(Theme.accentText(effectivePaletteStyle))
                                 : AnyShapeStyle(.white))
                // Die Farbe springt, sie fährt NICHT mit. Nachgemessen: der
                // grüne Glas-Tint verschwindet beim Einklappen sofort,
                // während eine interpolierte Schriftfarbe noch ein paar
                // Bilder lang fast weiß ist — genau dann steht ein weißes
                // Plus auf hellem Glas und der Knopf sieht für einen
                // Wimpernschlag verschwunden aus.
                .animation(nil, value: collapsed)
                .frame(width: Theme.Metrics.control, height: Theme.Metrics.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(BubbleButtonStyle(reduceMotion: reduceMotion))
        .modifier(ChromeGlass(id: "chrome-add", namespace: glassNamespace,
                              kind: .circle,
                              accent: collapsed ? nil : effectivePaletteStyle,
                              union: chromeUnion("chrome-add-solo")))
        // Fallback (iOS < 26): hier ist der Anlegen-Kreis eine EIGENE View —
        // die Zoom-Quelle sitzt direkt auf ihm (iOS 18–25; unter 18 blendet
        // das Cover schlicht).
        .modifier(MoreZoomSource(id: Self.createZoomID, namespace: createZoomNamespace))
        .accessibilityLabel(CreateAccessibility.label)
        .accessibilityIdentifier(CreateAccessibility.identifier)
    }

    // Bewusst KEIN `.tabViewBottomAccessory`: die Zubehörleiste ist Apples
    // Now-Playing-Slot (volle Breite, persistenter Status). Als Anlegen-
    // Aktion belegt sie dauerhaft einen Streifen über dem Raster —
    // ausprobiert, sieht nach echtem Glas aus, ist aber die falsche Rolle.

    /// Der Rückgängig-Toast: dieselbe Glas-Pille wie die Sync-Rückmeldung,
    /// nur mit einer Aktion darin. Er sitzt IM Chrom-Stapel und damit immer
    /// über dem Blob — kein Überlappen, egal ob der + gerade in der Ecke
    /// steht oder in der Kapsel klebt.
    ///
    /// Der Zeitgeber hängt an `.task(id:)`: ein neuer Check-in ersetzt den
    /// Toast, SwiftUI bricht die alte Aufgabe ab und startet die neue — die
    /// vier Sekunden laufen also von vorn los, statt sich zu stapeln.
    @ViewBuilder
    private var undoToast: some View {
        if let toast = undo.current {
            actionToast(label: {
                Text(toast.message)
                    .font(.footnote)
                    .lineLimit(1)
            }, actionTitle: String(localized: "Rückgängig"),
                         actionIdentifier: "undo-action") {
                    performUndo()
            }
            .transition(reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("undo-toast")
            .task(id: toast.id) {
                #if DEBUG
                let lifetime = ProcessInfo.processInfo.arguments.contains("-show-toast") ? 30 : 4
                #else
                let lifetime = 4
                #endif
                try? await Task.sleep(for: .seconds(lifetime))
                guard !Task.isCancelled else { return }
                withToastAnimation { undo.expire(toast.id) }
            }
        }
    }

    private func actionToast<Label: View>(
        @ViewBuilder label: () -> Label,
        actionTitle: String,
        actionIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Metrics.gap) {
            label()
            Divider().frame(height: 16)
            Button(action: action) {
                Text(actionTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText(effectivePaletteStyle))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(actionIdentifier)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .appToastSurface()
    }

    /// Kurzlebige Sync-Rückmeldung — eine kleine Glas-Pille über dem Chrom.
    @ViewBuilder
    private var syncBadge: some View {
        if !syncStatus.isEmpty {
            Text(syncStatus)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .appToastSurface()
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("sync-status")
        }
    }

    // MARK: – Deep-Links (haiity://habits|more|stats|archive|search|new)

    private func handleDeepLink(_ url: URL) {
        guard let destination = AppDestination.resolve(url: url) else { return }
        handle(destination)
    }

    private func handle(_ destination: AppDestination) {
        let effect = destination.effect
        routePresentationTask?.cancel()
        // Die Bereiche mit eigenem Kaufblatt (Mehr, Statistik) räumen es an
        // diesem Zähler weg. Das Blatt DIESES Bildschirms läuft dagegen
        // durch die Zustandsmaschine — nur sie weiß, wann das Zufahren
        // abgeschlossen ist.
        routeToken &+= 1
        let route = routeWork.begin(effect)
        pendingRoute = route
        if !effect.opensSearch {
            if #unavailable(iOS 26) { searching = false }
            search = ""
            committedSearch = ""
        }
        advance(route)
    }

    private func paywallDidPresent(_ context: PaywallContext) {
        guard paywall == context else { return }
        paywallIsPresented = true
    }

    /// Zufahren heisst: entweder war ein Deep-Link der Grund (dann gewinnt
    /// er), oder der Kauf ist durch und die unterbrochene Handlung läuft
    /// weiter. Beides erst HIER — eine Präsentation, die im Abgang der
    /// vorigen startet, schluckt iOS.
    private func deliverPendingPaywallDismissalRoute() {
        guard paywall == nil else { return }
        paywallIsPresented = false
        if pendingRoute == nil {
            resumeAfterPurchase()
        } else {
            purchasedIntent = nil
        }
        advancePendingRoute()
    }

    /// Nach dem Kauf weiterlaufen, statt den Nutzer vor derselben Wand
    /// abzusetzen. Hier zählt nur `.habits`: die übrigen Kontexte gehören
    /// den Einstellungen (siehe MoreView) oder entsperren sich selbst.
    private func resumeAfterPurchase() {
        guard let intent = purchasedIntent else { return }
        purchasedIntent = nil
        // Wieder durch dasselbe Tor — es lässt jetzt durch.
        if intent == .habits { requestCreate() }
    }

    private func deliverPendingCreateDismissalRoute() {
        // A newer create route may have re-presented the cover while an older
        // dismissal callback was still queued. That callback must not mark
        // the newly presented cover as gone.
        guard !showAdd else { return }
        createCover.didDismiss()
        advancePendingRoute()
    }

    private func createCoverDidPresent() {
        guard showAdd else { return }
        createCover.didPresent()
    }

    private func presentMoreSheet(_ route: MoreRoute) {
        if #available(iOS 26, *) {
            moreRoutePresentationTask?.cancel()
            // A presented sheet keeps its original content closure alive when
            // its item changes. Unmount first, then present the new route so
            // Darstellung can never reuse Verhalten & Teilen's view tree.
            if morePageRoute != nil {
                morePageRoute = nil
                moreRoutePresentationTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    presentedMoreDestination = presentedMorePage(for: route)
                    morePageRoute = route
                }
            } else {
                presentedMoreDestination = presentedMorePage(for: route)
                morePageRoute = route
            }
        } else {
            guard moreSheet != route else { return }
            if moreSheet != nil {
                moreSheet = nil
                moreRoutePresentationTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    presentedMoreDestination = presentedMorePage(for: route)
                    moreSheet = route
                }
            } else {
                presentedMoreDestination = presentedMorePage(for: route)
                moreSheet = route
            }
        }
    }

    private func handleProEntitlementChange(old: Bool, new: Bool) {
        applyCloudPreferences()
        guard old && !new else { return }
        // StoreKit can revoke an entitlement while the app is alive. Surface
        // the same global gate used by the feature limits immediately.
        guard paywall == nil else { return }
        paywall = .settings
    }

    private func moreSheetDidPresent(_ route: MoreRoute) {
        guard moreSheet == route || morePageRoute == route else { return }
        moreSheetIsPresented = true
        presentedMoreDestination = presentedMorePage(for: route)
    }

    private func dismissMoreSheet() {
        moreRoutePresentationTask?.cancel()
        moreRoutePresentationTask = nil
        moreSheet = nil
        morePageRoute = nil
    }

    private func deliverPendingMoreDismissalRoute() {
        // A stale callback must not clear a newer sheet that is already bound.
        guard moreSheet == nil, morePageRoute == nil else { return }
        moreSheetIsPresented = false
        presentedMoreDestination = nil
        advancePendingRoute()
    }

    private func advancePendingRoute() {
        guard let route = pendingRoute, routeWork.isCurrent(route) else {
            pendingRoute = nil
            return
        }
        advance(route)
    }

    private func advance(_ route: RouteWork.Item) {
        let presentation = RoutePresentation(
            create: createCover.phase(requested: showAdd),
            paywall: paywall != nil
                ? .presented : paywallIsPresented ? .dismissing : .absent,
            more: moreSheet != nil || morePageRoute != nil
                ? .presented : moreSheetIsPresented ? .dismissing : .absent,
            morePage: presentedMoreDestination)

        switch routeWork.nextStep(for: route, presentation: presentation) {
        case .dismissPaywall:
            let waitsForOnDismiss = paywallIsPresented
            paywall = nil
            if !waitsForOnDismiss { advance(route) }
        case .waitForPaywallDismissal:
            break
        case .dismissCreate:
            let waitsForOnDismiss = createCover.dismissalIsOwed
            showAdd = false
            if !waitsForOnDismiss { advance(route) }
        case .dismissMore:
            let waitsForOnDismiss = moreSheetIsPresented
            dismissMoreSheet()
            if !waitsForOnDismiss { advance(route) }
        case .waitForCreateDismissal, .waitForMoreDismissal:
            break
        case .keepCurrentMorePage:
            pendingRoute = nil
            nativeTab = .more
        case .apply:
            pendingRoute = nil
            apply(route)
        case nil:
            if pendingRoute == route { pendingRoute = nil }
        }
    }

    private func apply(_ route: RouteWork.Item) {
        guard routeWork.isCurrent(route) else { return }
        nativeTab = route.effect.tab
        requestedHabitID = route.effect.habitID

        routePresentationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, routeWork.isCurrent(route) else { return }

            if let morePage = route.effect.morePage {
                presentMoreSheet(moreRoute(for: morePage))
            } else if route.effect.opensSearch {
                openSearch(routeGeneration: route.generation)
            } else if route.effect.opensCreate {
                // Auch der Deep-Link ist ein Anlege-Einstieg und muss durch
                // dasselbe Tor: sonst wäre `haiity://create` die Abkürzung,
                // mit der das Limit gar nicht erst gefragt wird.
                requestCreate()
            }
            if route.effect.runsNativeSyncCleanup {
                cleanupNativeEntries()
            }
        }
    }

    /// Welches Deep-Link-Ziel dieses Blatt bedient. `about` und `developer`
    /// bedienen keins — kein Link führt dorthin, und die Routen-Maschine darf
    /// sie deshalb jederzeit wegräumen.
    private func appMoreDestination(for route: MoreRoute) -> AppMoreDestination? {
        switch route {
        case .archive: .archive
        case .about, .developer, .appearance, .habitBehavior, .github, .localModel: nil
        }
    }

    /// Interactive More pages are presented from their own rows. Keep that
    /// presentation map separate from the external route whitelist above,
    /// which intentionally only accepts the archive deep link.
    private func presentedMorePage(for route: MoreRoute) -> AppMoreDestination? {
        switch route {
        case .archive: .archive
        case .about: .about
        case .developer: .developer
        case .appearance: .appearance
        case .habitBehavior: .habitBehavior
        case .github: .github
        case .localModel: nil
        }
    }

    private func moreRoute(for destination: AppMoreDestination) -> MoreRoute {
        switch destination {
        case .archive: .archive
        case .about: .about
        case .developer: .developer
        case .appearance: .appearance
        case .habitBehavior: .habitBehavior
        case .github: .github
        }
    }

    #if DEBUG
    /// Nur Debug: `simctl launch … -screen stats` springt direkt zu einem
    /// Bereich — für Screenshot-Verifikation ohne UI-Automatisierung.
    private func handleLaunchScreenArgument() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-dump-sharecard") { dumpShareCards() }
        if args.contains("-dump-widgets") { dumpWidgets() }
        // Nur Debug: nach extern eingespielter data.json die Widget-Timeline
        // neu ziehen — sonst zeigt das Widget bis Mitternacht den alten Stand.
        if args.contains("-reload-widgets") { WidgetCenter.shared.reloadAllTimelines() }
        // Nur Debug: den Einrichtungs-Bildschirm direkt zeigen — Klicks
        // durch „Mehr" sind in der Sim-Automatisierung unzuverlässig.
        if args.contains("-show-reminder-setup") { showReminderSetup = true }
        // Nur Debug: Glückwunsch-Merker löschen bzw. Alias setzen — `simctl
        // defaults write` schreibt an den App-Group-Defaults VORBEI.
        if args.contains("-reset-celebration") {
            (UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard)
                .removeObject(forKey: Celebration.celebratedKey)
        }
        if let a = args.firstIndex(of: "-set-alias"), a + 1 < args.count {
            PersonalName.alias = args[a + 1]
        }
        if let a = args.firstIndex(of: "-apple-user-id"), a + 1 < args.count {
            PersonalName.appleUserID = args[a + 1]
        }
        if args.contains("-show-toast") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                withToastAnimation {
                    undo.present(habitId: UUID(), entries: [], message: "Training erledigt")
                }
            }
        }
        // Nur Debug: `-pro on|off` schaltet den Kauf-Merker ohne Kauf — sonst
        // wäre kein Gate im Simulator prüfbar. Der Haken klemmt den Zustand
        // fest (siehe Pro.setDebugUnlocked): dieser Aufruf steht NACH
        // `await boot()`, der dort gestartete Bestandsabgleich antwortet aber
        // später und würde ihn sonst wieder wegräumen.
        if let p = args.firstIndex(of: "-pro"), p + 1 < args.count {
            Pro.setDebugUnlocked(args[p + 1] != "off")
            trace("pro: debug hook \(args[p + 1])")
        }
        // Nur Debug: `-calendar-sync on|off` schaltet den Kalender-Spiegel
        // ohne UI — für die EventKit-Verifikation per Screenshot.
        if let c = args.firstIndex(of: "-calendar-sync"), c + 1 < args.count {
            let mode = args[c + 1]
            Task { @MainActor in
                if mode == "off" {
                    CalendarSync.disable()
                    trace("calsync: debug hook disabled")
                } else if await CalendarSync.requestAccess() {
                    CalendarSync.isEnabled = true
                    await CalendarSync.reconcile(habits: store.habits,
                                           defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                    trace("calsync: debug hook enabled")
                }
            }
        }
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return }
        if args[i + 1] == "notification-actions" {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                nativeTab = .more
                presentMoreSheet(.habitBehavior)
            }
            return
        }
        if args[i + 1] == "appearance" {
            let requestedMaterial = args.firstIndex(of: "-appearance-material")
                .flatMap { index in
                    index + 1 < args.count ? AppearanceMaterial(rawValue: args[index + 1]) : nil
                }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                if let requestedMaterial {
                    var preferences = store.appearancePreferences
                    preferences.material = requestedMaterial
                    store.appearancePreferences = preferences
                }
                nativeTab = .more
                presentMoreSheet(.appearance)
            }
            return
        }
        guard let url = URL(string: "haiity://\(args[i + 1])") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            handleDeepLink(url)
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Testdaten-Hooks. Schreibt in den echten App-Group-Store, deshalb
    /// simulator-only — siehe die Begründung am Aufruf.
    private func handleLaunchTestData() {
        let args = ProcessInfo.processInfo.arguments
        let reminderInteractionID = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!

        if args.contains("-seed-stats") {
            if store.activeTrackedHabits.isEmpty {
                var habit = Habit(name: "UI test habit")
                habit.log[DayKey.today()] = 1
                store.add(habit)
            }
            viewPreferences.update {
                $0.statsCards = StatsCardPrefs(active: StatsCard.allCases, customized: true)
            }
        }
        if args.contains("-seed-reminder-interactions") {
            if store.habits.contains(where: { $0.id == reminderInteractionID }) {
                store.remove(reminderInteractionID)
            }
            var reminder = Habit(name: "UI test reminder", itemType: .reminder)
            reminder.id = reminderInteractionID
            // Keep the fixture actionable without invoking the production
            // early-completion confirmation, regardless of the test clock.
            reminder.timeMinutes = 0
            reminder.repeatsWhileIncomplete = false
            reminder.calendarSyncEnabled = false
            store.add(reminder)
        }
        if args.contains("-cleanup-reminder-interactions"),
           store.habits.contains(where: { $0.id == reminderInteractionID }) {
            store.remove(reminderInteractionID)
        }
    }
    #endif

    /// Nur Debug: rendert JEDE Widget-Oberfläche in ihren echten Maßen in den
    /// App-Group-Container. WidgetKit lässt sich nicht fernsteuern — weder
    /// die Galerie noch das Kontrollzentrum; so ist jede Familie trotzdem
    /// reproduzierbar prüfbar.
    ///
    /// Drei Dinge, die diese Prüfung ernst nehmen muss:
    ///  * **Beide Schemata.** Dynamische Systemfarben lösen im ImageRenderer
    ///    nicht nach der SwiftUI-Umgebung auf, sondern nach
    ///    `UITraitCollection.current` — deshalb läuft jeder Durchgang IN
    ///    einer passenden Trait-Collection und setzt zusätzlich
    ///    `\.colorScheme`.
    ///  * **Beide Datenlagen.** Der echte (geseedete) Store zeigt, wie es
    ///    aussieht; die vier Grenzfälle zeigen, dass nichts bricht.
    ///  * **Alle Rendermodi.** Sperrbildschirm-Widgets werden nie in Farbe
    ///    gezeichnet. `\.widgetRenderingMode` ist — anders als
    ///    `\.widgetFamily` — von außen SETZBAR, der Modus lässt sich also
    ///    echt durchspielen statt geraten.
    @MainActor
    private func dumpWidgets() {
        let dir = SharedStorage.dataURL().deletingLastPathComponent()
        let live = HaiityEntry(date: .now, habits: visibleActiveTrackedHabits, palettes: effectivePalettes)
        let entry = live.habits.isEmpty ? HaiityEntry.demo : live
        let githubEntry = HaiityEntry(date: .now,
                                      habits: [],
                                      palettes: effectivePalettes,
                                      graphSource: .github,
                                      githubSnapshot: GitHubContributionSnapshot.loadShared()
                                          ?? Self.demoGitHubSnapshot())

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let trait = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            trait.performAsCurrent {
                // Homescreen-Familien: echte Maße, echte Innenränder (16 pt).
                for (name, family, size) in Self.homeCanvases {
                    // Das Haupt-Widget gibt es nur klein und mittel — groß
                    // ist der Graph, dort wäre es dieselbe Karte mit Luft.
                    if family != .systemLarge {
                        write(HaiityWidgetView(entry: entry).content(family: family, dark: scheme == .dark),
                              named: "w-main-\(name)-\(suffix)", size: size, scheme: scheme, to: dir)
                    }
                    write(GraphWidgetView(entry: entry).content(family: family, dark: scheme == .dark),
                          named: "w-graph-\(name)-\(suffix)", size: size, scheme: scheme, to: dir)
                    write(GraphWidgetView(entry: githubEntry).content(family: family, dark: scheme == .dark),
                          named: "w-github-\(name)-\(suffix)", size: size, scheme: scheme, to: dir)
                    if family != .systemSmall {
                        write(RosterWidgetView(entry: entry).content(family: family, dark: scheme == .dark),
                              named: "w-roster-\(name)-\(suffix)", size: size, scheme: scheme, to: dir)
                    }
                }

                // Die Auswahl selbst: dasselbe Widget, zweiter Habit — der
                // sichtbare Beleg, dass die Instanz ihre eigene Einstellung
                // hat und nicht mehr am ersten Habit klebt.
                if entry.habits.count > 1 {
                    let picked = HaiityEntry(date: .now, habits: entry.habits,
                                             palettes: entry.palettes,
                                             selected: entry.habits[1].id)
                    write(HaiityWidgetView(entry: picked).content(family: .systemMedium, dark: scheme == .dark),
                          named: "w-main-selected-medium-\(suffix)",
                          size: CGSize(width: 364, height: 170), scheme: scheme, to: dir)
                }

                // Sperrbildschirm: jede Familie in JEDEM Rendermodus.
                for (modeName, mode) in Self.renderingModes {
                    write(RingAccessoryView(entry: entry).content(mode: mode),
                          named: "w-acc-circular-\(modeName)-\(suffix)",
                          size: CGSize(width: 76, height: 76), scheme: scheme, to: dir,
                          padding: 0, background: .accessory)
                    write(StreakAccessoryView(entry: entry).content(mode: mode, dark: scheme == .dark),
                          named: "w-acc-rectangular-\(modeName)-\(suffix)",
                          size: CGSize(width: 172, height: 76), scheme: scheme, to: dir,
                          padding: 0, background: .accessory)
                    write(InlineAccessoryView(entry: entry).content(mode: mode),
                          named: "w-acc-inline-\(modeName)-\(suffix)",
                          size: CGSize(width: 200, height: 26), scheme: scheme, to: dir,
                          padding: 0, background: .accessory)
                }

                // Kontrollzentrum: der Inhalt des Steuerungselements.
                if let habit = entry.habit {
                    write(HabitControlLabel(name: habit.name,
                                            emoji: habit.emoji,
                                            done: GoalEngine.dayCounts(habit: habit, day: DayKey.today()))
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                            .padding(12),
                          named: "w-control-\(suffix)",
                          size: CGSize(width: 160, height: 76), scheme: scheme, to: dir,
                          padding: 0, background: .control)
                }

                // Der reine Graph OHNE Habit. Eigener Abzug, weil er als
                // einziges Widget auch im Leerfall keine Schrift zeigen darf
                // — ein Raster aus l0-Zellen statt „Noch keine Habits".
                write(GraphWidgetView(entry: HaiityEntry(date: .now, habits: [],
                                                         palettes: effectivePalettes))
                        .content(family: .systemMedium, dark: scheme == .dark),
                      named: "w-graph-empty-\(suffix)",
                      size: CGSize(width: 364, height: 170), scheme: scheme, to: dir)

                // Grenzfälle, die früher gebrochen sind — nur die Hauptgröße.
                for (name, habits) in Self.edgeCases {
                    let edge = HaiityEntry(date: .now, habits: habits, palettes: effectivePalettes)
                    write(HaiityWidgetView(entry: edge).content(family: .systemSmall, dark: scheme == .dark),
                          named: "w-edge-\(name)-\(suffix)",
                          size: CGSize(width: 170, height: 170), scheme: scheme, to: dir)
                }
            }
        }
    }

    private static let homeCanvases: [(String, WidgetFamily, CGSize)] = [
        ("small", .systemSmall, CGSize(width: 170, height: 170)),
        ("medium", .systemMedium, CGSize(width: 364, height: 170)),
        ("large", .systemLarge, CGSize(width: 364, height: 382)),
    ]

    private static let renderingModes: [(String, WidgetRenderingMode)] = [
        ("fullcolor", .fullColor), ("accented", .accented), ("vibrant", .vibrant),
    ]

    private static var edgeCases: [(String, [Habit])] {
        var quantity = Habit(name: "Wasser", emoji: "💧", recurrence: Recurrence(target: 3))
        var long = Habit(name: "Lesen", emoji: "📚")
        var resting = Habit(name: "Sport", emoji: "🏃", recurrence: .weekdays([2, 4, 6]))
        for i in 0..<365 {
            guard let k = DayKey.shifted(DayKey.today(), by: -i) else { continue }
            if i % 4 != 0 { long.log[k] = 1 }
            quantity.log[k] = (i % 3) + 1
            if i % 7 == 2 { resting.log[k] = 1 }
        }
        return [("nohabits", []),
                ("emptylog", [Habit(name: "Neu", emoji: "🌱")]),
                ("quantity", [quantity]),
                ("year", [long]),
                ("notdue", [resting])]
    }

    private static func demoGitHubSnapshot() -> GitHubContributionSnapshot {
        let today = DayKey.today()
        let days = (0..<371).compactMap { offset -> GitHubContributionDay? in
            guard let date = DayKey.shifted(today, by: -offset) else { return nil }
            let level = offset.isMultiple(of: 7) ? 0 : (offset % 4) + 1
            return GitHubContributionDay(date: date, count: level * 2, level: level)
        }
        return GitHubContributionSnapshot(username: "enrzh", days: days, fetchedAt: .now)
    }

    /// Womit die Fläche hinterlegt wird. Der Sperrbildschirm hat kein
    /// Widget-Hintergrund — dort steht ein Wallpaper, und genau davor muss
    /// der Inhalt bestehen.
    private enum DumpBackground { case widget, accessory, control }

    @MainActor
    private func write<V: View>(_ view: V,
                                named name: String,
                                size: CGSize,
                                scheme: ColorScheme,
                                to dir: URL,
                                padding: CGFloat = 16,
                                background: DumpBackground = .widget) {
        let canvas = ZStack {
            switch background {
            case .widget:
                Color(.systemBackground)
            case .accessory:
                // Ein Verlauf als Ersatz-Wallpaper: eine einfarbige Fläche
                // würde jeden Kontrastfehler verstecken.
                LinearGradient(colors: [Color(red: 0.09, green: 0.11, blue: 0.20),
                                        Color(red: 0.30, green: 0.17, blue: 0.34)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .control:
                // Die Kachel des Kontrollzentrums zeichnet das System; hier
                // steht nur eine Fläche, die dem Schema folgt — sonst läge
                // schwarze Schrift auf schwarzem Grund.
                RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .padding(4)
            }
            view.padding(padding)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 3
        guard let png = renderer.uiImage?.pngData() else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Nur Debug: rendert die Teilen-Karte in BEIDEN Schemata in den
    /// App-Group-Container — so lässt sie sich prüfen, ohne durch das
    /// Teilen-Blatt zu klicken.
    @MainActor
    private func dumpShareCards() {
        guard let habit = visibleActiveTrackedHabits.first else { return }
        let dir = SharedStorage.dataURL().deletingLastPathComponent()
        for scheme in [ColorScheme.light, .dark] {
            guard let png = ShareCard.render(habit: habit, scheme: scheme, palette: effectivePalettes.style(for: habit))?.pngData() else { continue }
            let name = scheme == .dark ? "sharecard-dark.png" : "sharecard-light.png"
            try? png.write(to: dir.appendingPathComponent(name))
        }
    }
    #endif

    // MARK: – Boot / iCloud / Reminder
    //
    // Lokal ist die Wahrheit: `store` schreibt data.json synchron, das Widget
    // liest dieselbe Datei. iCloud ist der Spiegel — er wird beim Start, beim
    // Aktivwerden und nach lokalen Änderungen (entprellt) nachgezogen. Fällt
    // er aus, ändert das an der App nichts ausser der Statuszeile in „Mehr“.

    private func boot() async {
        // Kauf-Zustand: der Lauscher zuerst (er muss stehen, BEVOR StoreKit
        // eine ausstehende Transaktion meldet — sonst geht sie verloren).
        // The lifecycle refresh is upgrade-only unless StoreKit has provided
        // an authoritative transaction update or a successful restore.
        Pro.startTransactionListener()
        viewPreferences.onChange = {
            store.setViewPreferences(viewPreferences.preferences)
            NotificationPresenter.configureQuickActions(
                enabled: viewPreferences.preferences.notificationActionsEnabled,
                choices: viewPreferences.preferences.notificationActions.slots)
            schedulePush()
            scheduleMaintenance()
        }
        applyCloudPreferences()
        // Native callbacks are installed on a later foreground pass. EventKit
        // can synchronously contact its daemon even when the callback only
        // checks authorization, so it must not share the first interactive
        // window.
        store.onChange = {
            schedulePush()
        }
        store.onChangeKind = { change in
            guard change == .general else { return }
            scheduleMaintenance()
            // Glückwunsch, wenn dieser Check-in den Tag vollgemacht hat.
            Task { await Reminders.celebrateIfPerfectDay(store: store) }
        }
        store.onCalendarSyncNeeded = { scope in
            pendingCalendarSync = pendingCalendarSync?.merging(scope) ?? scope
            scheduleMaintenance()
        }
        initialBootReady = true
        startupMaintenanceTask?.cancel()
    }

    private func startNativeSyncObservers() {
        guard !nativeSyncRecoveryPending else { return }
        CalendarSync.startObserving(store: store)
        ReminderSync.startObserving(store: store)
    }

    private func performNativeSyncRecoveryIfNeeded() async {
        guard nativeSyncRecoveryPending else { return }
        let cleanup = await NativeSyncCleanup.run()
        guard cleanup.calendar && cleanup.reminders else { return }
        NativeSyncInstallation.completeRecovery()
        nativeSyncRecoveryPending = false
        startNativeSyncObservers()
    }

    /// Recovery is intentionally a foreground integration task rather than a
    /// startup task. This keeps reinstall cleanup correct without making the
    /// first visible screen wait for EventKit.
    private func performForegroundNativeMaintenance() async {
        nativeSyncRecoveryPending = NativeSyncInstallation.prepare()
        await performNativeSyncRecoveryIfNeeded()
        guard !Task.isCancelled, !nativeSyncRecoveryPending else { return }
        startNativeSyncObservers()
        integrationsReady = true

        // Activation only needs the cached mapping fast path; this avoids a
        // 200-year EventKit inventory scan every time the app becomes active.
        await CalendarSync.reconcile(habits: store.habits,
                               defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        ReminderSync.pullCompletions(into: store,
                                     defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        await ReminderSync.reconcile(habits: store.habits,
                                     defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                                     validate: false)
    }

    /// Foreground activation shares the startup task slot. The short delay
    /// lets the restored window and its first scroll settle before cloud,
    /// notification, or native-store work resumes.
    private func scheduleForegroundMaintenance() {
        startupMaintenanceTask?.cancel()
        startupMaintenanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await performForegroundMaintenance()
            guard !Task.isCancelled else { return }
            startupMaintenanceTask = nil
        }
    }

    private func performForegroundMaintenance() async {
        await syncNow(announce: false)
        guard !Task.isCancelled else { return }
        HomeShortcuts.update(habits: store.habits,
                             defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        await Task.yield()
        await rescheduleReminders()
        guard !Task.isCancelled else { return }
        await reconcileMotivationActivity()
        guard !Task.isCancelled else { return }

        await performForegroundNativeMaintenance()
        guard !Task.isCancelled else { return }
        await reconcileAppIcon()
    }

    /// Cache hydration and shortcut registration are useful after launch, but
    /// neither is part of the first interactive frame. The graph cache is
    /// decoded off the main actor; delaying its state update keeps the first
    /// list layout and first scroll independent from the 371-cell card.
    private func schedulePostLaunchHydration() {
        postLaunchHydrationTask?.cancel()
        postLaunchHydrationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            // The task is owned by the mounted content view and is canceled
            // when that view disappears. A transient scenePhase value during
            // launch must not silently discard the local cache hydration.
            guard !Task.isCancelled else { return }
            await github.boot()
            StartupMetrics.event("githubCacheHydrated")
            guard !Task.isCancelled else { return }
            HomeShortcuts.update(habits: store.habits,
                                 defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
            postLaunchHydrationTask = nil
        }
    }

    /// Alle Mitteilungen neu stellen. Die Zusammenfassungen tragen ZAHLEN und
    /// müssen nach jeder Änderung am Store neu gerechnet werden; Motivation
    /// und Habit-Weckrufe lesen im selben Lauf ihre Einstellungen von Platte.
    /// Darum hängt das hier an `store.onChange` und am Aktivwerden.
    private func rescheduleReminders() async {
        // Close completed past occurrences before deriving summaries and
        // notification plans. The current day remains actionable.
        store.resolveExpiredOccurrences()
        // Preserve the legacy reminder behavior for items that have not
        // opted into a custom result yet.
        store.materializeMissedReminderDays()
        let calendar = Calendar.current
        let today = DayKey.today(calendar: calendar)
        let daily = Reminders.dailySummaryPlan(
            minutes: store.summaryMinutes,
            status: store.dailyStatus(today,
                                      calendar: calendar,
                                      habits: visibleActiveHabits),
            calendar: calendar)
        // `fullWeek`: die Wochen-Mitteilung darf nicht ausfallen, nur weil
        // die Woche BIS HEUTE noch leer ist (Montag geöffnet, Termin am
        // Freitag) — geschuldet wird über die ganze Woche gezählt.
        let weekly = Reminders.weeklySummaryPlan(
            minutes: store.weeklySummaryMinutes,
            weekday: store.weeklySummaryWeekday,
            status: store.weeklyStatus(today,
                                       calendar: calendar,
                                       fullWeek: true,
                                       habits: visibleActiveHabits),
            calendar: calendar)
        await Reminders.reschedule(daily: daily, weekly: weekly)
    }

    private func reconcileMotivationActivity() async {
        await MotivationActivityManager.shared.reconcile(
            motivationMinutes: store.motivationMinutes,
            name: PersonalName.effective,
            delivery: store.motivationDelivery,
            source: store.motivationSource)
    }

    /// A local write is immediately durable and visible. Its secondary
    /// integrations can wait for a short quiet window so rapid edits do not
    /// each start their own notification, shortcut, and EventKit work, and
    /// so the Habits list can take a frame after an editor dismisses.
    private func scheduleMaintenance() {
        Task { @MainActor in
            await maintenance.schedule { @MainActor in
                guard !Task.isCancelled else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                await rescheduleReminders()
                guard !Task.isCancelled else { return }
                await reconcileMotivationActivity()
                guard !Task.isCancelled else { return }
                HaiityShortcuts.updateAppShortcutParameters()
                guard integrationsReady, !nativeSyncRecoveryPending else { return }
                let calendarScope = pendingCalendarSync
                pendingCalendarSync = nil
                if let calendarScope {
                    await CalendarSync.sync(scope: calendarScope,
                                            habits: store.habits,
                                            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                }
                await ReminderSync.reconcile(
                    habits: store.habits,
                    defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                    validate: false)
            }
        }
    }

    /// Cleans old native entries first, then rebuilds only the integrations
    /// the user currently has enabled. This is shared by the settings button
    /// and the Home Screen cleanup action.
    private func cleanupNativeEntries() {
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
            let message = nativeCleanupMessage(for: result)
            nativeSyncCleanupMessage = message
            await flash(message)
        }
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

    private func reconcileAppIcon() async {
        let wanted = store.matchAppIcon
            ? AppIcons.iconName(for: effectivePalettes.global, customs: effectivePalettes.customs)
            : AppIcons.validManualName(store.manualAppIconName)
        _ = await AppIcons.set(wanted)
    }

    private var localCloudPreferences: CloudPreferences {
        CloudPreferences(calendarSyncHabits: CalendarSync.syncHabits,
                         calendarSyncReminders: CalendarSync.syncReminders,
                         nativeReminderSync: ReminderSync.isEnabled,
                         shakeToReportEnabled: ShakeToReport.isEnabled,
                         notificationDND: NotificationPromptPreference.state)
    }

    /// Apply synced intent to the device-local integration settings. The
    /// following reconciliation pass remains permission- and ID-aware.
    private func applyCloudPreferences() {
        guard let preferences = store.cloudPreferences else { return }
        let effective = ProGate.restrictedCloudPreferences(preferences,
                                                           unlocked: Pro.isUnlocked)
        CalendarSync.syncHabits = effective.calendarSyncHabits
        CalendarSync.syncReminders = effective.calendarSyncReminders
        ReminderSync.isEnabled = effective.nativeReminderSync
        NotificationPromptPreference.state = effective.notificationDND
        ShakeToReport.isEnabled = effective.shakeToReportEnabled
    }

    /// Nach einer lokalen Änderung: entprellt hochschreiben. Mehrere Häkchen
    /// hintereinander werden EIN Upload (siehe PushDebouncer).
    private func schedulePush() {
        Task {
            await pushes.schedule {
                await syncNow(announce: true, pullFirst: false)
            }
        }
    }

    /// Ein Abgleich: Remote holen und mergen, dann den eigenen Stand
    /// schreiben. Nicht angemeldet oder offline heisst NICHT „Fehler“ — die
    /// App läuft vollständig weiter, der Status sagt nur, woran es liegt.
    @MainActor
    private func syncNow(announce: Bool, pullFirst: Bool = true) async {
        guard cloudStatus.isSignedIn else { cloudStatus.refresh(); return }
        do {
            if pullFirst, let remote = try await cloud.pull() {
                store.merge(remote: remote)
            }
            store.materializeGitHubShowsUsername()
            store.materializeCloudPreferences(fallback: localCloudPreferences)
            applyCloudPreferences()
            viewPreferences.adoptRemote(store.data.viewPreferences)
            NotificationPresenter.configureQuickActions(
                enabled: viewPreferences.preferences.notificationActionsEnabled,
                choices: viewPreferences.preferences.notificationActions.slots)
            // Pull and merge before touching the root payload timestamp. A
            // startup-only local preference write must not make remote habit
            // metadata look older than this device.
            store.setViewPreferences(viewPreferences.preferences)
            guard let payload = store.exportJSON() else {
                // A sync that produces nothing is not a success. Saying nothing
                // here meant the person tapped sync, saw nothing happen, and
                // learned nothing — the same shape of silent failure as the
                // unreadable file, one layer up.
                cloudStatus.noteFailure(CloudSyncError.unreadableLocal)
                return
            }
            try await cloud.push(payload) { remote in
                // EIN Merge in dieser App — der aus dem Store.
                if let remote {
                    await MainActor.run {
                        store.merge(remote: remote)
                        store.materializeGitHubShowsUsername()
                        store.materializeCloudPreferences(fallback: localCloudPreferences)
                        applyCloudPreferences()
                        viewPreferences.adoptRemote(store.data.viewPreferences)
                        NotificationPresenter.configureQuickActions(
                            enabled: viewPreferences.preferences.notificationActionsEnabled,
                            choices: viewPreferences.preferences.notificationActions.slots)
                    }
                }
                return await MainActor.run { store.exportJSON() ?? payload }
            }
            cloudStatus.noteSuccess()
            // BEWUSST keine Erfolgs-Pille („✓ in iCloud gesichert") mehr:
            // dass der Normalfall funktioniert, ist keine Nachricht — die
            // Pille meldete sich nach jedem Häkchen. Fehler blitzen weiterhin
            // auf (unten), und der Dauerzustand steht in „Mehr".
        } catch {
            cloudStatus.noteFailure(error)
            // Nur echte Fehler stören beim Abhaken; „offline“ steht in „Mehr“
            // — und in den ersten Sekunden nach Start/Aufwachen gar nichts
            // (kurzlebige CloudKit-Aufwach-Fehler, siehe `becameActiveAt`).
            if announce, !CloudSyncError.map(error).isTemporary,
               Date.now.timeIntervalSince(becameActiveAt) > 8 {
                await flash(error.localizedDescription)
            }
        }
    }

    /// Kurze Rückmeldung über dem Chrom, danach wieder weg.
    @MainActor
    private func flash(_ message: String) async {
        syncStatus = message
        try? await Task.sleep(for: .seconds(3))
        if syncStatus == message { syncStatus = "" }
    }
}

// MARK: – Glas-Hüllen


/// Quelle der Zoom-Transition (iOS 18+): markiert die Drei-Punkte-Blase oben
/// rechts als den Ort, aus dem die Mehr-Seite wächst. Darunter (iOS 17) tut
/// der Modifier nichts — der Cover blendet dann schlicht.
private struct MoreZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Gegenstück auf der Mehr-Seite: die Seite wächst aus der Quelle und
/// schrumpft beim Schließen in sie zurück.
private struct MoreZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

/// Compatibility drawer for iOS < 26, where the dedicated native search tab
/// is unavailable.
///
/// The field is only mounted while the fallback search is active.
private struct LegacySearchDrawer: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #unavailable(iOS 26), isPresented {
            content.searchable(text: $text,
                               isPresented: $isPresented,
                               placement: .navigationBarDrawer(displayMode: .always),
                               prompt: Text(prompt))
        } else {
            content
        }
    }
}

private extension View {
    func legacySearchDrawer(text: Binding<String>,
                            isPresented: Binding<Bool>,
                            prompt: String) -> some View {
        modifier(LegacySearchDrawer(text: text, isPresented: isPresented,
                                    prompt: prompt))
    }
}

/// Die Wasserblase beim Halten — die Rückmeldung der iOS-26-Glasleisten,
/// nachgebaut für die eigenen Chrom-Knöpfe: unter dem Finger schwillt der
/// Knopf federnd an und setzt sich beim Loslassen wieder. Der Scale sitzt am
/// LABEL (also unter dem Glas-Modifier des Aufrufers): das Zeichen atmet, die
/// Glasscheibe bleibt in Form — die Blase auf der Scheibe selbst besorgt
/// `glassEffect(.interactive())`, wo es echtes Glas gibt.
private struct BubbleButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 1.15 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

// MARK: – Der Anlegen-Kreis auf iOS 27
//
// Auf iOS 26 zeichnet ihn das System (Such-Rollen-Tab). Auf iOS 27 trägt
// dieser Trick nicht mehr und die richtige Rolle (`TabRole.prominent`) gibt
// es nur im SDK 27, mit dem diese App nicht ausgeliefert werden darf —
// ausführlich in `ContentView.nativeShell`. Bis es ein Release-Xcode 27
// gibt, steht der Kreis hier selbst.

/// Wo die schwebende System-Tableiste WIRKLICH steht — ausgemessen an der
/// echten Ansicht, nicht aus Sicherheitszonen gerechnet.
///
/// Warum nicht gerechnet: die Leiste hängt an der BILDSCHIRMKANTE, nicht an
/// der Sicherheitszone. Ein Gerät mit Home-Indikator hat unten 34 pt Zone,
/// eines ohne 0 — dieselbe Rechnung landet auf beiden auf verschiedenen
/// Linien (nachgemessen: auf dem 17 Pro Max saß der Kreis 34 pt ÜBER der
/// Kapsel, auf dem SE stimmte er). Gemessen stimmt beides: die Leiste meldet
/// dieselbe Geometrie relativ zur Unterkante (Kapsel 62 pt hoch mit 21 pt
/// Abstand, minimierter Teller 48 pt mit 28 pt — beide um DIESELBE Mittellinie).
///
/// Beobachtbar, damit ausschließlich der Kreis neu zeichnet und nicht der
/// ganze Bildschirm (dieselbe Lehre wie bei `ChromeScrollBox`).
@available(iOS 26, *)
@Observable final class TabBarPlatters {
    struct Placement: Equatable {
        /// Mittelpunkt des Kreises in Fensterkoordinaten. Er ist in BEIDEN
        /// Leisten-Zuständen derselbe — die Leiste schrumpft um ihre Mitte.
        var center: CGPoint
        /// Aktueller Durchmesser: die Höhe des gerade sichtbaren Tellers.
        var diameter: CGFloat
    }
    var placement: Placement?
    /// Wurde überhaupt je eine Leiste gefunden? Trennt „die Leiste ist gerade
    /// weg" (dann gehört auch der Kreis weg) von „hier misst nichts" (dann
    /// muss der Rückfallwert her).
    var everFound = false
}

/// Der Ausmesser: eine unsichtbare Ansicht, die im Fenster die Tableiste
/// sucht und ihre Teller meldet. Gelesen werden nur öffentliche
/// UIView-Eigenschaften (`frame`, `isHidden`, `alpha`) — keine private
/// Programmierschnittstelle, kein Verändern der Systemansichten.
@available(iOS 26, *)
private struct TabBarPlatterReader: UIViewRepresentable {
    let platters: TabBarPlatters
    /// Nur damit SwiftUI `updateUIView` aufruft, wenn sich einer dieser
    /// Zustände ändert — dann lohnt ein neuer Messversuch.
    let remeasureOn: [Bool]

    func makeUIView(context: Context) -> UIView { PlatterProbe(platters: platters) }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Mit zurückgesetztem Zähler: hat sich an der Oberfläche etwas
        // geändert (Suche zu, Farbe gewechselt), lohnt ein neuer Anlauf.
        (uiView as? PlatterProbe)?.measure(retrying: true)
    }
}

@available(iOS 26, *)
private final class PlatterProbe: UIView {
    private let platters: TabBarPlatters
    /// Ansichten, an denen ein Beobachter hängt. BEWUSST stark gehalten: eine
    /// Ansicht, die mit angemeldetem Beobachter abgeräumt wird, ist ein
    /// Absturz. Abgemeldet wird beim nächsten Ausmessen oder beim Abbau.
    private var observed: [UIView] = []
    /// Die Leiste steht nicht sofort im Fenster (und ist bei offener Suche
    /// zeitweise gar nicht da). Solange nichts zu messen ist, wird es in
    /// Ruhe noch einmal versucht, statt für immer auf den Rückfallwerten
    /// stehen zu bleiben.
    private var retries = 0
    private static let maxRetries = 40

    init(platters: TabBarPlatters) {
        self.platters = platters
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { unobserve() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { unobserve(); return }
        // Die Leiste steht erst NACH diesem Umlauf im Fenster.
        measure(retrying: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        measure(retrying: true)
    }

    /// Erneut ausmessen und dabei den Wiederhol-Zähler zurücksetzen — von
    /// aussen aufgerufen, wenn sich die Lage geändert haben kann (Suche zu,
    /// Farbe gewechselt).
    func measure(retrying: Bool) {
        if retrying { retries = 0 }
        measure()
    }

    /// Höchstens EIN wartender Versuch — sonst legt jedes Aktualisieren der
    /// Ansicht eine weitere Kette an.
    private var retryPending = false

    private func retryLater() {
        guard retries < Self.maxRetries, !retryPending else { return }
        retries += 1
        retryPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.retryPending = false
            self?.measure()
        }
    }

    /// Das Minimieren der Leiste ist kein Weg, den man interpolieren könnte:
    /// die Teller behalten ihre Rahmen, das System blendet den einen ein und
    /// den anderen aus (nachgemessen mit einem Bildtakt-Mitschnitt). Ein
    /// Beobachter auf `hidden` ist deshalb genau das richtige Signal — und es
    /// ist DAS DES SYSTEMS, nicht unsere eigene Scroll-Vermutung.
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        measure()
    }

    private func measure() {
        guard let window, let bar = Self.findTabBar(in: window) else {
            publish(nil)
            retryLater()
            return
        }
        let barFrame = bar.convert(bar.bounds, to: window)
        // Die „Teller" der Leiste: die Kapsel (ruhend) und der kleine Teller
        // (minimiert). Beide existieren immer, sichtbar ist einer.
        //
        // Erkannt werden sie an der LAGE, nicht am Klassennamen: ein Teller
        // ist ein Stück in Leistenhöhe, das VOLLSTÄNDIG in der Leiste liegt.
        // Das ist die Prüfung, die den Umbett-Behälter der Glas-Animation
        // aussortiert (100 × 100 an der Leistenkante — er ragt hinaus und
        // hätte als „größter Teller" die ganze Messung verdorben).
        let platterViews = bar.subviews.filter { view in
            let f = view.convert(view.bounds, to: window)
            return f.height >= 30 && f.height <= 90 && f.width >= 30
                && barFrame.insetBy(dx: -1, dy: -1).contains(f)
        }
        observe(bar: bar, platters: platterViews)
        // Bei offener Suche nimmt das System die Leiste aus dem Bild — der
        // Kreis gehört zu ihr und geht mit.
        guard !bar.isHidden, bar.alpha > 0.05, barFrame.intersects(window.bounds),
              // Der GRÖSSTE Teller ist die Kapsel: sie gibt Linie,
              // Randabstand und den ruhenden Durchmesser. (Der kleine Teller
              // sitzt um dieselbe Mitte, einer reicht also für die Linie.)
              let capsule = platterViews.max(by: { $0.bounds.height < $1.bounds.height })
        else {
            publish(nil)
            retryLater()
            return
        }
        let capsuleFrame = capsule.convert(capsule.bounds, to: window)
        // Der Abstand der Leiste zur Unterkante ist AUCH ihr Seitenabstand —
        // die schwebende Leiste ist rundum gleich eingerückt (nachgemessen in
        // beiden Zuständen, mit und ohne Home-Indikator).
        let gutter = window.bounds.maxY - capsuleFrame.maxY
        let resting = capsuleFrame.height
        guard gutter >= 0, gutter <= 60 else {
            trace("platter probe: implausible bar \(capsuleFrame) gutter \(gutter)")
            publish(nil)
            retryLater()
            return
        }
        retries = 0
        // Während des Umschaltens sind beide Teller kurz sichtbar; der
        // KLEINERE gewinnt, damit der Kreis mit dem Anfang der System-
        // Animation schrumpft statt an ihrem Ende zu springen.
        let shown = platterViews.filter { !$0.isHidden && $0.alpha > 0.05 }
        let diameter = shown.map(\.bounds.height).min() ?? resting
        publish(.init(center: CGPoint(x: window.bounds.maxX - gutter - resting / 2,
                                      y: capsuleFrame.midY),
                      diameter: min(max(diameter, 28), resting)))
    }

    /// Erst im nächsten Umlauf schreiben: `measure()` läuft auch aus
    /// `updateUIView`, und ein Zustandsschreiben MITTEN im Auswerten der
    /// Ansicht ist genau die Warnung, die man nicht ignorieren soll.
    private func publish(_ placement: TabBarPlatters.Placement?) {
        let found = placement != nil
        guard platters.placement != placement || (found && !platters.everFound) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if found { platters.everFound = true }
            guard platters.placement != placement else { return }
            platters.placement = placement
        }
    }

    private func observe(bar: UIView, platters: [UIView]) {
        let wanted = [bar] + platters
        guard observed.map(ObjectIdentifier.init) != wanted.map(ObjectIdentifier.init) else { return }
        unobserve()
        for view in wanted {
            view.addObserver(self, forKeyPath: "hidden", options: [], context: nil)
            view.addObserver(self, forKeyPath: "alpha", options: [], context: nil)
        }
        observed = wanted
    }

    private func unobserve() {
        for view in observed {
            view.removeObserver(self, forKeyPath: "hidden")
            view.removeObserver(self, forKeyPath: "alpha")
        }
        observed = []
    }

    /// Die Tableiste im Fenster. `UITabBar` ist eine ÖFFENTLICHE Klasse; ihre
    /// Teller sind es nicht, werden hier aber nur als gewöhnliche UIViews
    /// gelesen. Findet sich keine, meldet der Ausmesser schlicht nichts und
    /// der Kreis fällt auf die nachgemessenen Werte zurück.
    static func findTabBar(in view: UIView) -> UIView? {
        if view is UITabBar { return view }
        for sub in view.subviews.reversed() {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }
}

/// Der Anlegen-Kreis auf iOS 27: eigenes Glas, auf der Linie der gemessenen
/// Leiste — und zugleich die Quelle der Zoom-Transition der Anlegen-Seite.
@available(iOS 27, *)
private struct CreateCircle: View {
    let reduceMotion: Bool
    /// Zustände, deren Wechsel ein neues Ausmessen wert ist — der Wert selbst
    /// wird nie gelesen (siehe `remeasureOn` beim Aufruf).
    let remeasureOn: [Bool]
    let zoomID: String
    let zoomNamespace: Namespace.ID
    let action: () -> Void

    @State private var platters = TabBarPlatters()
    @Environment(\.appearancePreferences) private var appearancePreferences

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            if let placement = resolved(in: geo.size) {
                circle(diameter: placement.diameter)
                    .position(x: placement.center.x - origin.x,
                              y: placement.center.y - origin.y)
                    // Die Leiste morpht ihre Kapsel in rund einer halben
                    // Sekunde zum kleinen Teller (nachgemessen im Bildtakt);
                    // der Kreis geht denselben Weg statt zu springen.
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45),
                               value: placement.diameter)
                    .transition(.opacity)
            }
        }
        .background(TabBarPlatterReader(platters: platters, remeasureOn: remeasureOn))
        // Die Leiste sitzt an der Bildschirmkante, nicht in der
        // Sicherheitszone — der Kreis braucht dieselbe Fläche.
        .ignoresSafeArea()
    }

    /// Die gemessene Lage. Ist die Leiste GEFUNDEN, aber gerade nicht zu
    /// messen (das System hat sie aus dem Bild genommen), gehört der Kreis
    /// ebenfalls nicht ins Bild — er ist ein Teil von ihr. Nur wenn hier NIE
    /// eine Leiste gefunden wurde, tritt der nachgemessene Rückfallwert an
    /// ihre Stelle: lieber ein Kreis an der richtigen Stelle als gar keiner.
    private func resolved(in size: CGSize) -> TabBarPlatters.Placement? {
        if let measured = platters.placement { return measured }
        guard !platters.everFound else { return nil }
        return .init(center: CGPoint(x: size.width - CreateCircle.fallbackCenterInset,
                                     y: size.height - CreateCircle.fallbackCenterInset),
                     diameter: CreateCircle.fallbackDiameter)
    }

    private static let fallbackCenterInset: CGFloat = 52
    private static let fallbackDiameter: CGFloat = 62

    @ViewBuilder
    private func circle(diameter: CGFloat) -> some View {
        let button = Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                // Wie das System-Zeichen der Leiste, NICHT wie die
                // Markenfarbe: der Kreis auf iOS 26 trägt ein fast schwarzes
                // Plus (am Bildabzug gemessen: 30/30/33), und der Eigenbau
                // soll neben derselben Kapsel nicht anders aussehen.
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        // Halten-Blase wie an den eigenen Chrom-Knöpfen: das Zeichen atmet,
        // die Glasscheibe antwortet über `.interactive()`.
        let styledButton = button
            .buttonStyle(BubbleButtonStyle(reduceMotion: reduceMotion))
            .modifier(MoreZoomSource(id: zoomID, namespace: zoomNamespace))
            .accessibilityLabel(CreateAccessibility.label)
            .accessibilityIdentifier(CreateAccessibility.identifier)
        // `CreateCircle` is already `@available(iOS 27, *)`, so the glass style
        // is always in scope here. The `else` branch that used to carry a
        // `#available` guard was unreachable and only produced a warning.
        if appearancePreferences.performanceMode {
            styledButton
        } else {
            styledButton.glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

/// Deko fürs Empty-State: ein kleines zufälliges Contribution-Muster.
private struct DemoGrid: View {
    let palette: PaletteStyle
    // Einmal je View-Identität gewürfelt — während des gestaffelten
    // Auftritts darf das Muster nicht neu entstehen.
    private let pattern: [Int] = MotifGrid.randomPattern()

    var body: some View {
        MotifGrid(pattern: pattern, palette: palette)
    }
}
