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
    @State private var store = HabitStore()
    @State private var github = GitHubContributionStore()
    /// iCloud-Spiegel. Der lokale Stand in `store` ist die Wahrheit; das hier
    /// trägt ihn nur zur Apple-ID hinüber (siehe CloudSync).
    @State private var cloud = CloudSync()
    @State private var cloudStatus = CloudSyncStatus()
    /// Fasst schnelle Folgeänderungen zu EINEM Upload zusammen.
    @State private var pushes = PushDebouncer()
    @State private var editing: Habit?
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
    @State private var showReminderSetup = false
    /// Das Melde-Blatt (Schütteln). Es hängt hier oben, weil die Geste überall
    /// gilt — sie gehört keinem Bereich, sondern der App.
    @State private var showFeedback = false
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
    /// Das Unterziel bleibt während des Abgangs bekannt. So kann dieselbe
    /// Route vom bereits sichtbaren Ziel unterschieden werden, ohne neu zu
    /// präsentieren.
    @State private var presentedMoreDestination: AppMoreDestination?
    /// Wartet die Tab-Auswahl ab, bevor ein Deep-Link eine Präsentation
    /// auslöst. Ein neuer Link ersetzt eine noch ausstehende Präsentation.
    @State private var routePresentationTask: Task<Void, Never>?
    /// Sperrt bereits eingereihte Sucharbeit eines älteren Deep-Links.
    @State private var routeWork = RouteWork()
    /// Genau die letzte noch nicht angewandte Route. Beide Präsentations-
    /// callbacks prüfen ihren Generationstoken, bevor sie sie weiterreichen.
    @State private var pendingRoute: RouteWork.Item?
    /// Die synchronisierte Auswahl der Statistik-Karten und der festen
    /// kompakten Darstellung. Scrollen schreibt diesen Zustand nie.
    @State private var viewPreferences = ViewPreferencesStore()
    @State private var search = ""
    /// Suchfeld ausgeklappt? Startet IMMER `false` — das Feld ist Standard
    /// unsichtbar und erscheint erst auf Tippen (bzw. per haiity://search).
    @State private var searching = false
    /// Wohin die zugeklappte Suche zurückkehrt — der zuletzt gewählte
    /// echte Bereich (nie `.search` selbst).
    @State private var lastNonSearchTab: AppTab = .habits
    @State private var searchPresentationArmed = false
    @FocusState private var searchFieldFocused: Bool
    /// Der native EditButton schaltet die Griffleisten der Habit-Liste ein.
    /// Beim Filtern wird er geschlossen, weil die Move-Offsets dann nicht
    /// mehr auf die vollständige aktive Liste zeigen.
    @State private var editMode: EditMode = .inactive
    /// Scroll-Buchfuehrung fuer Nacharbeiten-Anker. Sie
    /// mutiert ohne Observation und verursacht keine Body-Invalidierungen.
    @State private var chrome = ChromeScrollBox()
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

    private var githubUsernameBinding: Binding<Bool> {
        Binding(get: { store.githubShowsUsername },
                set: { store.githubShowsUsername = $0 })
    }

    private static let listSpace = "habit-list"

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
            // NUR Fallback (iOS < 26): das selbstgebaute Chrom über der
            // Liste. Ab iOS 26 zeichnet die native TabView die Leiste selbst.
            .overlay(alignment: .bottom) { legacyBottomChrome }
            // Der Feld-Beobachter (nur iOS 27, nur bei offener Suche) —
            // absichtlich hier oben und nicht an der Liste: er darf nicht
            // mit ihr verschwinden, wenn sie gerade neu gebaut wird.
            .background { searchFieldWatcher }
            // Die drei Zeilen sind das ganze Theming-Gerüst: das Schema wird
            // fürs FENSTER gesetzt (Blätter inklusive), die Palette reist als
            // Umgebungswert bis in jede Rasterzelle, und der Tint zieht die
            // System-Steuerelemente mit. Alle drei hängen am Store, damit ein
            // Umstellen in „Mehr" sofort durchschlägt.
            .preferredColorScheme(store.appearance.colorScheme)
            .environment(\.palettes, store.palettes)
            .environment(\.appearancePreferences, store.appearancePreferences)
            // accentText statt accent: die Markenfarbe hat auf hellem Grund
            // nur ~3,4:1 — als Schrift/Symbolfarbe ist das zu wenig.
            .tint(Theme.accentText(store.paletteStyle))
            .onOpenURL { handleDeepLink($0) }
            .onReceive(NotificationCenter.default.publisher(
                for: NotificationActionRouter.pendingDidChange)) { _ in
                schedulePendingNotificationAction()
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
                    .themed(store)
                    .onAppear { paywallDidPresent(context) }
            }
            .sheet(item: $editing) {
                EditHabitSheet(store: store, existing: $0)
                    .themed(store)
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
            // Direkte Unterziele bleiben Blätter über dem aktuell sichtbaren
            // Bereich. Mehr-Zeilen präsentieren über `morePageRoute`.
            .sheet(item: $moreSheet,
                   onDismiss: deliverPendingMoreDismissalRoute) { route in
                NavigationStack {
                    moreDestination(route)
                        .navigationDestination(for: MoreRoute.self, destination: moreDestination)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(String(localized: "Fertig")) { dismissMoreSheet() }
                                    .accessibilityIdentifier("close-more-sheet")
                            }
                        }
                }
                .themed(store)
                .onAppear { moreSheetDidPresent(route) }
            }
            .fullScreenCover(isPresented: $showReminderSetup) {
                ReminderSetupView(isPresented: $showReminderSetup, store: store).themed(store)
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
                FeedbackSheet(store: store, cloudStatus: cloudStatus).themed(store)
            }
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                searchPresentationArmed = true
                becameActiveAt = .now
                #if DEBUG
                // Keep deterministic simulator routes independent of startup
                // sync, which can legitimately wait on iCloud.
                handleLaunchScreenArgument()
                #endif
                await boot()
                schedulePendingNotificationAction()
                schedulePendingShortcutLink()
                await github.boot()
                #if DEBUG
                if FrameProbe.enabled { FrameProbe.shared.start() }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    becameActiveAt = .now
                    schedulePendingNotificationAction()
                    schedulePendingShortcutLink()
                    // Widget-Intent kann data.json extern geändert haben —
                    // purer Re-Read (No-op bei unveränderter mtime).
                    store.reloadFromDisk()
                    viewPreferences.adoptRemote(store.data.viewPreferences)
                    // Konto kann sich ausserhalb der App geändert haben
                    // (an-/abgemeldet), und das andere Gerät kann gehakt
                    // haben, während diese App im Hintergrund lag.
                    cloudStatus.refresh()
                    Task {
                        await syncNow(announce: false)
                        await rescheduleReminders()
                        await reconcileMotivationActivity()
                        CalendarSync.reconcile(habits: store.habits,
                                               defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                                               validate: false)
                        ReminderSync.pullCompletions(into: store,
                                                     defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
                        ReminderSync.reconcile(habits: store.habits,
                                               defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                                               validate: false)
                        await reconcileAppIcon()
                    }
                    Task { await github.resumeOrRefresh(forced: true) }
                }
            }
            .onChange(of: search) { _, query in
                if !query.isEmpty { editMode = .inactive }
            }
            .onChange(of: showAdd) { _, open in
                trace("showAdd=\(open) searching=\(searching) focus=\(searchFieldFocused) tab=\(nativeTab)")
                // Der Zustandsmaschine melden: solange das Cover offen ist
                // (und im Fenster nach dem Zufahren) kann keine ECHTE
                // Lupen-Berührung eine Suche präsentieren.
                chrome.searchFlow.coverChanged(open: open)
                guard open else { return }
                editMode = .inactive
                // Dieselbe Hygiene wie beim Öffnen der Mehr-Seite: das Cover
                // verdeckt Liste, Toast und Karte vollständig.
                undo.clear()
                backfill = nil
            }
            .onChange(of: nativeTab) { old, tab in
                trace("nativeTab \(old)->\(tab) showAdd=\(showAdd) searching=\(searching) focus=\(searchFieldFocused)")
                // Wohin das Zuklappen der Suche zurückkehrt: der letzte
                // echte Bereich, nicht stur „Habits".
                if tab != .search { lastNonSearchTab = tab }
                // Der Such-Tab ist ein ECHTES Ziel (siehe nativeShell) — die
                // Auswahl bleibt stehen. Beim Betreten klappt das Feld auf
                // und die Tastatur kommt mit (das Fotos-Verhalten: EIN Tipp
                // auf den Kreis, tippen kann man sofort) …
                if tab == .search, old != .search, backfill == nil {
                    openSearch(origin: .toolbar)
                }
                // … und beim Verlassen räumt die App den Suchzustand selbst
                // weg: das System schreibt beim Tab-Wechsel nicht zuverlässig
                // `false` zurück, und eine gefilterte Liste hinter einem
                // anderen Tab wäre genau der „Habits sind
                // verschwunden"-Zustand.
                guard old == .search, tab != .search else { return }
                if searching { searching = false }
                searchFieldFocused = false
                clearSearchTextAfterCollapse()
            }
            .onChange(of: searchFieldFocused) { _, focused in
                trace("focus=\(focused) searching=\(searching) showAdd=\(showAdd)")
                // Ein TRUE-Fokus bei GESCHLOSSENER Suche präsentiert AUF
                // iOS 26 unter `.minimize` das Feld sofort wieder — genau der
                // Kreislauf, der dort das X mehrfach drücken ließ: das System
                // schreibt beim Abbrechen kurz `focus = true`, und je nach
                // Reihenfolge landet das NACH unserem Löschen. Dort also hart
                // klemmen: Fokus gibt es nur bei offener Suche. (`openSearch`
                // setzt `searching` VOR dem Fokus, der legitime Weg bleibt
                // frei.)
                //
                // Auf iOS 27 hängt an dieser Klemme nichts mehr: dort
                // präsentiert das System die Suche gar nicht selbst (siehe
                // `SearchableHidden`), ein Fokus ohne offene Suche kann also
                // nichts aufklappen. Sie bleibt trotzdem stehen — für den
                // Fall, dass ein Nachzügler-Fokus doch einmal durchkommt,
                // ist „Fokus nur bei offener Suche" auch dort richtig.
                if focused && !searching { searchFieldFocused = false }
            }
            .onChange(of: searching) { _, open in
                trace("searching=\(open) focus=\(searchFieldFocused) showAdd=\(showAdd) tab=\(nativeTab)")
                if open {
                    guard searchPresentationArmed else {
                        searching = false
                        searchFieldFocused = false
                        return
                    }
                    // JEDES `true` läuft durch die Zustandsmaschine: die
                    // System-Lupe ist willkommen, Nachzügler (Re-Present
                    // mitten im Zuklappen, verspätete Such-Aktivierung des
                    // Such-Rollen-Tabs rund ums Anlegen-Cover) werden im
                    // selben Umlauf zurückgeschrieben — dieselbe Klemme wie
                    // beim Fokus, nur eine Ebene höher.
                    guard chrome.searchFlow.systemPresented() else {
                        trace("REVERT spurious search present")
                        searching = false
                        searchFieldFocused = false
                        return
                    }
                } else {
                    chrome.searchFlow.dismissed()
                }
                // Beim Schließen den Fokus AKTIV löschen: bleibt das
                // `searchFocused`-Binding wahr, präsentiert das System das
                // Feld sofort wieder (X → Kreis → Leiste klappt wieder auf).
                if !open {
                    searchFieldFocused = false
                    clearSearchTextAfterCollapse()
                    // Zuklappen heißt VERLASSEN: zurück auf den vorherigen
                    // Bereich, damit die Leiste in den Such-KREIS
                    // zurückschrumpft — auf dem Such-Tab stehen zu bleiben
                    // ließe das Feld als leere Leiste liegen. Routen (Deep-
                    // Links) setzen ihr Ziel gleich danach selbst; der kurze
                    // Zwischenschritt stört sie nicht.
                    if nativeTab == .search {
                        returnFromSearchAfterCollapse()
                    }
                }
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
            // Über der Liste, unter dem Fallback-Chrom (das `body` DANACH
            // auflegt): der Rückgängig-Toast im Chrom-Stapel bleibt über der
            // offenen Karte antippbar.
            .overlay { backfillLayer }
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
    /// **Der Such-Tab ist jetzt eine echte Suche.** Sein `.searchable` hängt
    /// an SEINEM Inhalt (der gefilterten Habit-Liste), nicht mehr am
    /// Habits-Tab: nur so klappt das System die Leiste UNTEN aus dem
    /// Suchkreis auf und fährt sie mit der Tastatur hoch — genau die
    /// Fotos-Mechanik. Der alte Umweg (Such-Rolle abfangen, Suchfeld als
    /// Drawer OBEN am Habits-Tab präsentieren) sprang sichtbar an die
    /// falsche Kante.
    ///
    /// Die früheren iOS-27-Verrenkungen (`TabRole.prominent` hinter
    /// `#if compiler`, Auswahl-Abfangen des Such-Rollen-Tabs) sind damit
    /// gegenstandslos: die Such-Rolle wird nicht mehr zweckentfremdet,
    /// sondern genau so benutzt, wie das System sie verdrahtet. Der
    /// Feld-Beobachter für den iOS-27-Binding-Fehler (Zuklappen schreibt
    /// kein `false` zurück) bleibt als Sicherheitsnetz bestehen — er greift
    /// nur, wenn er wirklich ein Zuklappen misst.
    @available(iOS 26, *)
    private var nativeShell: some View {
        TabView(selection: $nativeTab) {
            Tab(String(localized: "Statistik"), systemImage: "chart.bar",
                value: AppTab.stats) {
                statsTabContent
            }
            Tab(String(localized: "Habits"), systemImage: "square.grid.2x2",
                value: AppTab.habits) {
                habitsTabContent
            }
            Tab(String(localized: "Mehr"), systemImage: "ellipsis",
                value: AppTab.more) {
                moreTabContent
            }
            // Kurzer Tab-Titel: auf iOS 27 steht der Such-Tab MIT
            // Beschriftung in der Kapsel („Habits durchsuchen" sprengte sie).
            Tab(String(localized: "Suchen"), systemImage: "magnifyingglass",
                value: AppTab.search, role: .search) {
                searchTabContent
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // A TabView's native bar is outside the content overlay. Reserving a
        // bottom inset here keeps the toast above both its collapsed and
        // expanded states instead of letting the bar paint over it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !searching {
                floatingPills
                    .padding(.bottom, Theme.Metrics.control + Theme.Metrics.gap)
            }
        }
    }

    /// Der Statistik-Tab: die frühere Mehr-Unterseite als eigener Bereich.
    @available(iOS 26, *)
    private var statsTabContent: some View {
        NavigationStack {
            StatsView(store: store, viewPreferences: viewPreferences,
                      routeToken: routeToken)
        }
    }

    /// Der Inhalt des Such-Tabs: DIESELBEN Karten, gefiltert. Leerer
    /// Suchbegriff zeigt die volle Liste — der Tab ist damit auch ohne
    /// Eingabe kein weißes Loch (dasselbe Verhalten wie Fotos).
    @available(iOS 26, *)
    private var searchTabContent: some View {
        NavigationStack {
            Group {
                if store.activeHabits.isEmpty {
                    emptyState
                } else {
                    searchList
                }
            }
            .navigationTitle(String(localized: "Suchen"))
            .searchable(text: $search,
                        isPresented: $searching,
                        prompt: Text(String(localized: "Habits und Erinnerungen durchsuchen")))
            .searchFocused($searchFieldFocused)
        }
    }

    @available(iOS 26, *)
    private var searchList: some View {
        List {
            if filteredHabits.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(filteredHabits.enumerated()), id: \.element.id) { index, habit in
                    row(for: habit, index: index + 1, inSearchTab: true)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppearanceBackground(preferences: store.appearancePreferences))
    }

    /// Der Inhalt des Habits-Tabs — EINE Quelle für beide Leisten-Varianten.
    @available(iOS 26, *)
    private var habitsTabContent: some View {
        ZStack {
            AppearanceBackground(preferences: store.appearancePreferences)
            habitsStack
        }
        // Die Nacharbeiten-Karte ÜBER der Liste, aber UNTER den
        // schwebenden Pillen: der Rückgängig-Toast ist das Zurück zu
        // genau dem, was die Karte gerade geschrieben hat, und muss
        // bei offener Karte antippbar bleiben — dieselbe Schichtung
        // wie im Fallback (Karte unter dem Chrom-Stapel).
        .overlay { backfillLayer }
    }

    @available(iOS 26, *)
    private var moreTabContent: some View {
        NavigationStack {
            MoreView(store: store, github: github, cloudStatus: cloudStatus,
                     statsCards: viewPreferences,
                     onOpen: presentMoreSheet,
                     routeToken: routeToken)
                .navigationTitle(String(localized: "Mehr"))
        }
        .sheet(item: $morePageRoute,
               onDismiss: deliverPendingMoreDismissalRoute) { route in
            NavigationStack {
                moreDestination(route)
                    // Die versteckte Tür in „Über" SCHIEBT den
                    // Entwicklerbereich in dieses Blatt (siehe MoreRoute).
                    .navigationDestination(for: MoreRoute.self, destination: moreDestination)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(String(localized: "Fertig")) { dismissMoreSheet() }
                                .accessibilityIdentifier("close-more-sheet")
                        }
                    }
            }
            .themed(store)
            .onAppear { moreSheetDidPresent(route) }
        }
    }

    private var fallbackMoreContent: some View {
        NavigationStack {
            MoreView(store: store, github: github, cloudStatus: cloudStatus,
                     statsCards: viewPreferences,
                     onOpen: presentMoreSheet,
                     routeToken: routeToken)
                .navigationTitle(String(localized: "Mehr"))
        }
    }

    private var fallbackStatsContent: some View {
        NavigationStack {
            StatsView(store: store, viewPreferences: viewPreferences,
                      routeToken: routeToken)
        }
    }

    /// Rückgängig-Toast und Sync-Pille als schwebende Schicht — in der
    /// Fallback-Leiste stecken sie im Chrom-Stapel, hier sind sie die ganze
    /// Schicht.
    private var floatingPills: some View {
        VStack(spacing: Theme.Metrics.gap) {
            undoToast
            syncBadge
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.bottom, Theme.Metrics.gap)
    }

    private var habitsStack: some View {
        NavigationStack {
            habitsScreen
        }
    }

    // MARK: – Die Anlegen-Seite

    /// Die Anlegen-Seite: dasselbe Formular wie bisher im Half-Sheet
    /// (EditHabitSheet bringt seinen eigenen NavigationStack samt
    /// Sichern-Knopf mit), jetzt als volle Seite mit X oben links
    /// (`asPage`). Ziel der Zoom-Transition: sie wächst aus dem
    /// Anlegen-Knopf und schrumpft dorthin zurück.
    private var createPage: some View {
        EditHabitSheet(store: store, asPage: true)
            .themed(store)
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
                                   showsUsername: githubUsernameBinding)
            case .appearance:
                MoreView(store: store, github: github, cloudStatus: cloudStatus,
                         statsCards: viewPreferences, onOpen: presentMoreSheet,
                         routeToken: routeToken, screen: .appearance)
            case .habitBehavior:
                MoreView(store: store, github: github, cloudStatus: cloudStatus,
                         statsCards: viewPreferences, onOpen: presentMoreSheet,
                         routeToken: routeToken, screen: .habitBehavior)
            case .timeZone:
                MoreView(store: store, github: github, cloudStatus: cloudStatus,
                         statsCards: viewPreferences, onOpen: presentMoreSheet,
                         routeToken: routeToken, screen: .timeZone)
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
    ///
    /// Ab iOS 26 heißt „Suche öffnen": den ECHTEN Such-Tab wählen und dann
    /// sein `searchable(isPresented:)` aufklappen — dieselbe Mechanik, die
    /// auch ein Tipp auf den Suchkreis auslöst. Erst der Zustand, dann im
    /// nächsten Umlauf der Fokus; beides im selben Umlauf verschluckt die
    /// Präsentation (nachgemessen, gilt unverändert).
    private func openSearch(origin: SearchOpenOrigin, routeGeneration: Int? = nil) {
        trace("openSearch(\(origin)) showAdd=\(showAdd)")
        // Absicht anmelden, BEVOR das Binding springt: `onChange` fragt die
        // Maschine im selben Umlauf, und ein `open`-Zustand winkt durch.
        chrome.searchFlow.userOpened()
        if #available(iOS 26, *), nativeTab != .search { nativeTab = .search }
        DispatchQueue.main.async {
            guard routeWorkIsCurrent(routeGeneration) else { return }
            withAnimation { searching = true }
            DispatchQueue.main.async {
                guard routeWorkIsCurrent(routeGeneration) else { return }
                searchFieldFocused = true
            }
        }
    }

    private func routeWorkIsCurrent(_ generation: Int?) -> Bool {
        guard let generation else { return true }
        return routeWork.isCurrent(generation)
    }

    /// Der zweite iOS-27-Fehler, abgefangen: das System klappt die Suche zu,
    /// schreibt aber KEIN `false` ins Binding zurück (`\.isSearching` bleibt
    /// ebenfalls wahr — nachgemessen) und reisst das halb zugeklappte Feld
    /// deshalb sofort wieder auf. Also wird das Feld an der ECHTEN Ansicht
    /// vermessen und der Zustand daran angeglichen, bevor das Zurückreissen
    /// einsetzt. Hier steht nur die Messung; entschieden wird in
    /// `SearchFlow.fieldReading`.
    ///
    /// Nur iOS 27: auf iOS 26 kommt das `false` sauber zurück, und ein
    /// zweiter Weg zum selben Zustand ist ein zweiter Weg, ihn zu verlieren.
    @ViewBuilder
    private var searchFieldWatcher: some View {
        if #available(iOS 27, *) {
            SearchFieldWatcher(active: searching) { reading in
                reconcileSearchField(reading)
            }
        }
    }

    private func reconcileSearchField(_ reading: SearchFieldReading) {
        guard chrome.searchFlow.fieldReading(reading) else { return }
        trace("watcher: system dismissed the search -> isPresented=false")
        searching = false
        searchFieldFocused = false
        // … und den Suchbegriff mit. Auf iOS 26 räumt SwiftUI ihn beim
        // Schließen selbst weg (nachgemessen: getippt, X getippt, Liste
        // wieder vollständig). Auf iOS 27 kommt das Schließen nie bei
        // SwiftUI an, also räumt hier auch niemand auf — und die Liste bliebe
        // gefiltert, ohne dass noch ein Suchfeld zu sehen wäre, in dem man
        // das ablesen oder rückgängig machen könnte. Genau ein Zustand, in
        // dem Habits verschwunden aussehen.
        clearSearchTextAfterCollapse()
    }

    /// Der Suchbegriff leert sich erst NACH der Zuklapp-Animation — und
    /// ohne Übergang.
    ///
    /// Sofortiges Leeren fiel mitten in das Zuklappen: `search` filtert
    /// BEIDE montierten Listen (Habits-Tab UND Such-Tab), und das animierte
    /// Zurückfluten aller Zeilen — jede ein 371-Zellen-Raster — riss die
    /// Animation auf 22 Bilder je Sekunde mit einem 650-ms-Stand
    /// (FrameProbe, iOS-27-Simulator; vom Gerät als „dropping fps"
    /// gemeldet). Verzögert und ohne Animation ist das Auffüllen reine
    /// Buchhaltung hinter einer bereits ruhigen Oberfläche.
    private func clearSearchTextAfterCollapse() {
        guard !search.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            // Wieder offen (oder längst geleert): nichts anfassen — sonst
            // frisst der Nachzügler eine frisch getippte Suche.
            guard !searching else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { search = "" }
        }
    }

    /// Let the native search field finish shrinking into its own tab item
    /// before changing the selected tab. Animating both operations in one
    /// transaction makes iOS 27 briefly interpolate a detached glass circle
    /// through the content area.
    private func returnFromSearchAfterCollapse() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !searching, nativeTab == .search else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { nativeTab = lastNonSearchTab }
        }
    }

    /// Aus dem Such-Tab heraus zu Nacharbeiten: erst zurück zu Habits (dort
    /// wohnen Karte, Vorhang und Anker-Messung), dann öffnen. Die kurze
    /// Pause lässt den Tab-Wechsel und das Zuklappen der Suche setzen.
    private func redirectBackfillFromSearch(_ habit: Habit, day: String) {
        if searching { searching = false }
        searchFieldFocused = false
        search = ""
        nativeTab = .habits
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            openBackfill(habit, day: day, afterMenu: false)
        }
    }

    private var filteredHabits: [Habit] {
        let active = store.activeHabits
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return active }
        return active.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.emoji.contains(q)
        }
    }

    @ViewBuilder
    private var habitsScreen: some View {
        if store.activeHabits.isEmpty && github.snapshot == nil {
            emptyState
                .navigationTitle("Habits")
                .legacySearchDrawer(text: $search,
                                    isPresented: $searching,
                                    focus: $searchFieldFocused,
                                    prompt: String(localized: "Habits und Erinnerungen durchsuchen"))
                .toolbar { createToolbarItem }
        } else {
            habitList
                // Wieder der ECHTE große Titel: die Statistik-Karten, die
                // einst ÜBER ihm scrollen mussten, wohnen im eigenen Tab —
                // damit gehört „Habits" der Navigationsleiste und bekommt
                // das native Einklappen beim Scrollen zurück (der
                // Zeilen-Titel blieb beim Scrollen einfach stehen und ließ
                // eine leere Glasleiste zurück).
                .navigationTitle("Habits")
                .environment(\.editMode, $editMode)
                .legacySearchDrawer(text: $search,
                                    isPresented: $searching,
                                    focus: $searchFieldFocused,
                                    prompt: String(localized: "Habits und Erinnerungen durchsuchen"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                withAnimation {
                                    editMode = editMode == .active ? .inactive : .active
                                }
                            } label: {
                                Label(editMode == .active
                                      ? String(localized: "Sortieren beenden")
                                      : String(localized: "Habits sortieren"),
                                      systemImage: "arrow.up.arrow.down")
                            }
                            .disabled(!search.isEmpty)
                            .accessibilityIdentifier("reorder-habits")

                            Button { presentMoreSheet(.archive) } label: {
                                Label(String(localized: "Archiv"), systemImage: "archivebox")
                            }
                            .accessibilityIdentifier("open-archive")
                        } label: {
                            Label(String(localized: "Bearbeiten"), systemImage: "ellipsis")
                        }
                        .accessibilityIdentifier("habit-management")
                    }
                    createToolbarItem
                }
        }
    }

    @ToolbarContentBuilder
    private var createToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if editMode == .active {
                Button {
                    withAnimation { editMode = .inactive }
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(String(localized: "Fertig"))
                .accessibilityIdentifier("finish-reordering")
            } else {
                Button { requestCreate() } label: {
                    Image(systemName: "plus")
                }
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
        if #available(iOS 26, *) { return store.activeHabits }
        return filteredHabits
    }

    private var habitList: some View {
        List {
            if let snapshot = github.snapshot {
                GitHubContributionCard(snapshot: snapshot,
                                       collapsed: collapsed,
                                       showsUsername: store.githubShowsUsername,
                                       openProfile: { GitHubLink.open(snapshot.profileURL) })
                    .equatable()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0,
                                              leading: Theme.Metrics.gutter,
                                              bottom: 0,
                                              trailing: Theme.Metrics.gutter))
            }
            if habitsTabSource.isEmpty {
                if github.snapshot == nil || !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(Array(habitsTabSource.enumerated()), id: \.element.id) { index, habit in
                    // + 1: Messfühler 0 gehört der Titelzeile (sie ist immer
                    // da und damit der stabile Anker der Scroll-Messung).
                    row(for: habit, index: index + 1)
                }
                .onMove(perform: search.isEmpty
                    ? { store.move(fromOffsets: $0, toOffset: $1) }
                    : nil)
            }
        }
        .listStyle(.plain)
        // Das Chrom liegt ÜBER der Liste. Ohne diese Boden-Marge endet der
        // scrollbare Inhalt genau darunter — auf schmalen Geräten und in den
        // Accessibility-Größen verdeckt es dann dauerhaft das Raster der
        // letzten Karte, und zwar in RTL genauso.
        .contentMargins(.bottom, chromeFootprint, for: .scrollContent)
        // Karten sind weiß/#1C1C1E, die Seite muss also die gruppierte
        // Fläche sein. Kein toolbarBackground-Override — die Navigations-
        // leiste behält ihr System-Glas.
        .scrollContentBackground(.hidden)
        .background(AppearanceBackground(preferences: store.appearancePreferences))
        .coordinateSpace(.named(Self.listSpace))
        .onPreferenceChange(RowOffsetKey.self) { frames in
            handleScroll(frames)
        }
    }

    /// Fußabdruck des Chroms: Knopfhöhe + Abstand zur Unterkante + Luft. Der
    /// Wert ist ABSICHTLICH unabhängig vom Zusammenziehen — würde die Marge
    /// mitschrumpfen, verschöbe sich der Inhalt, das Scroll-Signal bekäme
    /// eine Bewegung ohne Finger und der Umschalter triebe sich selbst.
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

    private func habitToday(_ habit: Habit) -> String {
        DayKey.today(calendar: habitCalendar(for: habit))
    }

    // Die Statistik-Karten über dem Titel sind in den eigenen
    // Statistik-Tab umgezogen (siehe StatsView) — die Habit-Liste beginnt
    // wieder mit ihrem Titel.

    // Der Zeilen-Titel („Habits" als Listenzeile) ist Geschichte: er
    // existierte nur, damit die Statistik-Karten über ihm scrollen konnten.
    // Messfühler 0 entfiel mit ihm; die Zeilen behalten ihre Indizes ab 1.

    @ViewBuilder
    private func row(for habit: Habit, index: Int, inSearchTab: Bool = false) -> some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("row")
        #endif
        switch ItemPresentation.forItem(habit) {
        case .reminderRow:
            ReminderRow(habit: habit,
                        onToggle: { toggleReminder(habit) },
                        onEdit: { editing = habit },
                        onArchive: { store.archive(habit.id) },
                        calendar: habitCalendar(for: habit))
                .equatable()
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        requestReminderCompletion(habit)
                    } label: {
                        Label(String(localized: "Erledigt"), systemImage: "checkmark")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        revertReminder(habit)
                    } label: {
                        Label(String(localized: "Zurücksetzen"),
                              systemImage: "arrow.uturn.backward")
                    }
                    .tint(.gray)
                }
                .background { if !inSearchTab { rowProbe(index) } }
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
                onToggleDay: { toggleDay(habit, day: $0) },
                onSelectDay: { day in
                    if inSearchTab { redirectBackfillFromSearch(habit, day: day) }
                    else { openBackfill(habit, day: day, afterMenu: false) }
                },
                onBackfill: {
                    if inSearchTab { redirectBackfillFromSearch(habit, day: habitToday(habit)) }
                    else { openBackfill(habit, day: habitToday(habit), afterMenu: true) }
                },
                onIncrement: { increment(habit) },
                onClear: { revert(habit) },
                onMarkDone: { markDone(habit) },
                onEdit: { editing = habit },
                onArchive: { store.archive(habit.id) },
                onAnswer: { answer(habit, yes: $0) },
                leadingSwipe: reveal.leading,
                trailingSwipe: reveal.trailing,
                calendar: habitCalendar(for: habit))
                .equatable()
                .background { if !inSearchTab { rowProbe(index) } }
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
        guard let habit = store.habits.first(where: { $0.id == request.target.habitID }),
              habit.archivedAt == nil else { return }
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

    private func schedulePendingNotificationAction() {
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else { return }
            handlePendingNotificationAction()
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
        let calendar = habitCalendar(for: reminder)
        let state = ReminderOccurrenceEngine.state(for: reminder, calendar: calendar)
        guard let occurrence = state.actionable else { return }
        if occurrence.dueDate > .now {
            earlyReminderCompletion = PendingReminderCompletion(habitID: reminder.id,
                                                                day: occurrence.day)
        } else {
            completeReminder(reminder, occurrence: occurrence)
        }
    }

    private func confirmEarlyReminderCompletion() {
        guard let pending = earlyReminderCompletion,
              let reminder = store.habits.first(where: { $0.id == pending.habitID }),
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
        let calendar = habitCalendar(for: reminder)
        let cursor = reminder.repeatsWhileIncomplete ? nil
            : ReminderOccurrenceEngine.cursorAfterCompleting(occurrence,
                                                             reminder: reminder,
                                                             calendar: calendar)
        store.setReminderCompletion(reminder.id, day: occurrence.day,
                                    completed: true, nextCursor: cursor)
        Theme.Haptics.check()
    }

    private func revertReminder(_ reminder: Habit) {
        let calendar = habitCalendar(for: reminder)
        let state = ReminderOccurrenceEngine.state(for: reminder, calendar: calendar)
        guard let completed = state.mostRecentCompleted else { return }
        store.setReminderCompletion(reminder.id, day: completed.day,
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
        let request = BackfillRequest(habitId: habit.id, day: day,
                                      anchor: backfillAnchor(for: habit))
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
        guard let habit = store.habits.first(where: { $0.id == habitId }) else { return }
        let allowed = days.filter { Backfill.canWrite(habit: habit, day: $0) }.sorted()
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
        guard let habit = store.habits.first(where: { $0.id == habitId }) else { return }
        let allowed = entries.filter { Backfill.canWrite(habit: habit, day: $0.day) }
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

    /// Der Anker, aus dem die Nacharbeiten-Karte wächst: die Zeile des
    /// Habits, dessen langer Druck (bzw. Zellentipp) sie öffnet — als
    /// Bildschirmanteil (0…1). Die Zeilenlagen liegen schon in der
    /// Chrom-Kiste (die Scroll-Messung schreibt sie bei jedem Bild); hier
    /// wird nur beim ÖFFNEN einmal gelesen. Der feste Aufschlag (~halbe
    /// Kartenhöhe) zielt auf die Mitte des Rasters statt auf die Oberkante;
    /// die Klemme hält den Anker auf dem Bildschirm, wenn die Zeile gerade
    /// halb hinausgescrollt ist. Ohne Messwert (Zeile nicht sichtbar,
    /// gefilterte Liste): Bildmitte — das alte Verhalten, nie etwas
    /// Schlechteres.
    private func backfillAnchor(for habit: Habit) -> UnitPoint {
        guard let index = habitsTabSource.firstIndex(where: { $0.id == habit.id }),
              let rowTop = chrome.rowFrames[index + 1] else { return .center }
        let height = Self.windowHeight()
        guard height > 0 else { return .center }
        let y = (Self.windowSafeTop() + rowTop + 110) / height
        return UnitPoint(x: 0.5, y: min(0.92, max(0.08, y)))
    }

    /// Höhe bzw. obere Sicherheitszone des AKTIVEN Fensters — dieselbe
    /// Begründung wie `HabitCard.windowWidth`: im Split View ist das Fenster
    /// nicht der Bildschirm.
    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow
    }

    private static func windowHeight() -> CGFloat {
        if let height = activeWindow()?.bounds.height, height > 0 { return height }
        return UIScreen.main.bounds.height
    }

    private static func windowSafeTop() -> CGFloat {
        activeWindow()?.safeAreaInsets.top ?? 0
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
    private var backfillLayer: some View {
        if let request = backfill,
           let habit = store.habits.first(where: { $0.id == request.habitId }) {
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

    /// Meldet die Oberkante JEDER sichtbaren Zeile. Aus zwei Momentaufnahmen
    /// fällt das exakte Scroll-Delta (alle sichtbaren Zeilen wandern um
    /// denselben Betrag) — das ist der einzige Weg, der unter iOS 17 UND in
    /// einer faulen `List` trägt: ein einzelner Messfühler am Listenanfang
    /// wird beim Scrollen abgeräumt und meldet nichts mehr.
    private func rowProbe(_ index: Int) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: RowOffsetKey.self,
                                   value: [index: geo.frame(in: .named(Self.listSpace)).minY])
        }
    }

    private func handleScroll(_ frames: [Int: CGFloat]) {
        // Ebenfalls Buchführung: die Zeilenlagen für den Anker der
        // Nacharbeiten-Karte (siehe `backfillAnchor`).
        chrome.rowFrames = frames
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DemoGrid(palette: store.paletteStyle)
            Text(String(localized: "Noch keine Habits"))
                .font(.title3.bold())
            Text(String(localized: "Lege deinen ersten Eintrag an."))
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
                    .background(Theme.accentFill(store.paletteStyle), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-first-habit")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppearanceBackground(preferences: store.appearancePreferences))
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
                    Capsule().fill(Theme.accent(store.paletteStyle).opacity(0.18))
                }
            }
            .foregroundStyle(selected
                             ? AnyShapeStyle(Theme.accentText(store.paletteStyle))
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
                                 ? AnyShapeStyle(Theme.accentText(store.paletteStyle))
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
                              accent: collapsed ? nil : store.paletteStyle,
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
            HStack(spacing: Theme.Metrics.gap) {
                Text(toast.message)
                    .font(.body)
                    .lineLimit(1)
                Divider().frame(height: 16)
                Button {
                    performUndo()
                } label: {
                    Text(String(localized: "Rückgängig"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accentText(store.paletteStyle))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("undo-action")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .modifier(ToastSurface())
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

    /// Kurzlebige Sync-Rückmeldung — eine kleine Glas-Pille über dem Chrom.
    @ViewBuilder
    private var syncBadge: some View {
        if !syncStatus.isEmpty {
            Text(syncStatus)
                .font(.footnote)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .modifier(ToastSurface())
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
            // The first queued search callback may have run just before this
            // route arrived. A non-search route still wins in that ordering.
            if searching {
                searching = false
            } else {
                chrome.searchFlow.dismissed()
            }
            searchFieldFocused = false
            search = ""
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
        presentedMoreDestination = appMoreDestination(for: route)
        if #available(iOS 26, *) {
            morePageRoute = route
        } else {
            moreSheet = route
        }
    }

    private func moreSheetDidPresent(_ route: MoreRoute) {
        guard moreSheet == route || morePageRoute == route else { return }
        moreSheetIsPresented = true
        presentedMoreDestination = appMoreDestination(for: route)
    }

    private func dismissMoreSheet() {
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

        routePresentationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, routeWork.isCurrent(route) else { return }

            if let morePage = route.effect.morePage {
                presentMoreSheet(moreRoute(for: morePage))
            } else if route.effect.opensSearch {
                openSearch(origin: .deepLink, routeGeneration: route.generation)
            } else if route.effect.opensCreate {
                // Auch der Deep-Link ist ein Anlege-Einstieg und muss durch
                // dasselbe Tor: sonst wäre `haiity://create` die Abkürzung,
                // mit der das Limit gar nicht erst gefragt wird.
                requestCreate()
            }
        }
    }

    /// Welches Deep-Link-Ziel dieses Blatt bedient. `about` und `developer`
    /// bedienen keins — kein Link führt dorthin, und die Routen-Maschine darf
    /// sie deshalb jederzeit wegräumen.
    private func appMoreDestination(for route: MoreRoute) -> AppMoreDestination? {
        switch route {
        case .archive: .archive
        case .about, .developer, .appearance, .habitBehavior, .timeZone, .github: nil
        }
    }

    private func moreRoute(for destination: AppMoreDestination) -> MoreRoute {
        switch destination {
        case .archive: .archive
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
                    CalendarSync.reconcile(habits: store.habits,
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
        // Kurz warten: `searchable(isPresented:)` schluckt ein `true`, das
        // gesetzt wird, bevor die Suchleiste im Toolbar-Baum hängt.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            handleDeepLink(url)
        }
    }

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
        let live = HaiityEntry(date: .now, habits: store.activeTrackedHabits, palettes: store.palettes)
        let entry = live.habits.isEmpty ? HaiityEntry.demo : live
        let githubEntry = HaiityEntry(date: .now,
                                      habits: [],
                                      palettes: store.palettes,
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
                                                         palettes: store.palettes))
                        .content(family: .systemMedium, dark: scheme == .dark),
                      named: "w-graph-empty-\(suffix)",
                      size: CGSize(width: 364, height: 170), scheme: scheme, to: dir)

                // Grenzfälle, die früher gebrochen sind — nur die Hauptgröße.
                for (name, habits) in Self.edgeCases {
                    let edge = HaiityEntry(date: .now, habits: habits, palettes: store.palettes)
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
        guard let habit = store.activeTrackedHabits.first else { return }
        let dir = SharedStorage.dataURL().deletingLastPathComponent()
        for scheme in [ColorScheme.light, .dark] {
            guard let png = ShareCard.render(habit: habit, scheme: scheme, palette: store.palettes.style(for: habit))?.pngData() else { continue }
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
        HaiityShortcuts.updateAppShortcutParameters()
        // Kauf-Zustand: der Lauscher zuerst (er muss stehen, BEVOR StoreKit
        // eine ausstehende Transaktion meldet — sonst geht sie verloren), der
        // Bestandsabgleich nebenher. Beides bewusst ohne `await`: die Gates
        // lesen den lokalen Merker, keine Ansicht wartet auf das Netz.
        Pro.startTransactionListener()
        Task { await Pro.refresh() }
        ReminderSync.startObserving(store: store)
        store.onChange = {
            schedulePush()
        }
        store.onChangeKind = { change in
            guard change == .general else { return }
            Task {
                await rescheduleReminders()
                await reconcileMotivationActivity()
            }
            // Glückwunsch, wenn dieser Check-in den Tag vollgemacht hat.
            Task { await Reminders.celebrateIfPerfectDay(store: store) }
            // Kalender-Spiegel nachziehen (No-op ohne Schalter/Zugriff;
            // ohne `validate`, damit Check-ins EventKit gar nicht anfassen).
            CalendarSync.reconcile(habits: store.habits,
                                   defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                                   validate: false)
            ReminderSync.reconcile(habits: store.habits,
                                   defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                                   validate: false)
            // Habit-Namen können sich geändert haben -> Siri-Phrasen auffrischen.
            HaiityShortcuts.updateAppShortcutParameters()
        }
        viewPreferences.onChange = {
            store.setViewPreferences(viewPreferences.preferences)
            NotificationPresenter.configureQuickActions(
                enabled: viewPreferences.preferences.notificationActionsEnabled,
                choices: viewPreferences.preferences.notificationActions.slots)
            schedulePush()
            Task { await rescheduleReminders() }
        }
        applyCloudPreferences()
        await syncNow(announce: false)
        applyCloudPreferences()
        await rescheduleReminders()
        await reconcileMotivationActivity()
        CalendarSync.reconcile(habits: store.habits,
                               defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        ReminderSync.pullCompletions(into: store,
                                     defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        ReminderSync.reconcile(habits: store.habits,
                               defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        await reconcileAppIcon()
        if ReminderSetup.shouldPresent(completed: UserDefaults.standard.bool(forKey: ReminderSetup.completedKey)) {
            showReminderSetup = true
        }
    }

    /// Alle Mitteilungen neu stellen. Die Zusammenfassungen tragen ZAHLEN und
    /// müssen nach jeder Änderung am Store neu gerechnet werden; Motivation
    /// und Habit-Weckrufe lesen im selben Lauf ihre Einstellungen von Platte.
    /// Darum hängt das hier an `store.onChange` und am Aktivwerden.
    private func rescheduleReminders() async {
        let calendar = Calendar.current
        let today = DayKey.today(calendar: calendar)
        let daily = Reminders.dailySummaryPlan(
            minutes: store.summaryMinutes,
            status: store.dailyStatus(today, calendar: calendar),
            calendar: calendar)
        // `fullWeek`: die Wochen-Mitteilung darf nicht ausfallen, nur weil
        // die Woche BIS HEUTE noch leer ist (Montag geöffnet, Termin am
        // Freitag) — geschuldet wird über die ganze Woche gezählt.
        let weekly = Reminders.weeklySummaryPlan(
            minutes: store.weeklySummaryMinutes,
            weekday: store.weeklySummaryWeekday,
            status: store.weeklyStatus(today, calendar: calendar, fullWeek: true),
            calendar: calendar)
        await Reminders.reschedule(daily: daily, weekly: weekly)
    }

    private func reconcileMotivationActivity() async {
        await MotivationActivityManager.shared.reconcile(
            motivationMinutes: store.motivationMinutes,
            name: PersonalName.effective,
            delivery: store.motivationDelivery)
    }

    private func reconcileAppIcon() async {
        let wanted = store.matchAppIcon
            ? AppIcons.iconName(for: store.palettes.global, customs: store.palettes.customs)
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
        CalendarSync.syncHabits = preferences.calendarSyncHabits
        CalendarSync.syncReminders = preferences.calendarSyncReminders
        ReminderSync.isEnabled = preferences.nativeReminderSync
        NotificationPromptPreference.state = preferences.notificationDND
        ShakeToReport.isEnabled = preferences.shakeToReportEnabled
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
            // Pull and merge before touching the root payload timestamp. A
            // startup-only local preference write must not make remote habit
            // metadata look older than this device.
            store.setViewPreferences(viewPreferences.preferences)
            guard let payload = store.exportJSON() else { return }
            try await cloud.push(payload) { remote in
                // EIN Merge in dieser App — der aus dem Store.
                if let remote {
                    await MainActor.run {
                        store.merge(remote: remote)
                        store.materializeGitHubShowsUsername()
                        store.materializeCloudPreferences(fallback: localCloudPreferences)
                        applyCloudPreferences()
                        viewPreferences.adoptRemote(store.data.viewPreferences)
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

// MARK: – Scroll-Signal

/// Ein Messbild des System-Suchfeldes (siehe `SearchFieldProbe`).
struct SearchFieldReading: Equatable {
    /// Steht überhaupt ein Suchfeld im Fenster?
    var present: Bool
    /// Seine Breite in Punkten (0, wenn keins da ist).
    var width: CGFloat
    /// Hält es die Eingabe (`isFirstResponder`)?
    var focused: Bool

    static let none = SearchFieldReading(present: false, width: 0, focused: false)
}

/// Herkunft einer ausdrücklich angeforderten Suche. Nur ein Deep-Link muss
/// den minimierten System-Toolbar-Modus verlassen.
enum SearchOpenOrigin: CustomStringConvertible {
    case toolbar
    case deepLink

    var description: String {
        switch self {
        case .toolbar: "toolbar"
        case .deepLink: "deepLink"
        }
    }
}

/// Die Such-Präsentation als EXPLIZITE Zustandsmaschine — rein, ohne SwiftUI,
/// testbar. Sie beendet das Whack-a-Mole der Geräte-Rückmeldungen („X schließt
/// nicht in einem Tipp", „Anlegen-Schließen öffnet die Suche"): beides sind
/// SYSTEM-Schreibvorgänge auf das `isPresented`-Binding, die zeitlich NACH
/// unserem eigenen Zustand landen — auf dem Gerät anders getaktet als im
/// Simulator. Statt Timer nachzustimmen, entscheidet hier ein Regelwerk, ob
/// eine Präsentation GEWOLLT sein kann:
///
///  * `userOpened` (Deep-Link, Fallback-Knopf): Absicht — gilt immer.
///  * `systemPresented` (das Binding springt auf `true`, ohne dass wir es
///    waren — die System-Lupe, aber auch jeder Nachzügler): erlaubt NUR, wenn
///    weder gerade geschlossen wird noch das Anlegen-Cover im Spiel ist.
///     – Im Schließ-Fenster (`closeSettle` nach dem Zuklappen) ist es der
///       bekannte Re-Present des Systems mitten in der Abklapp-Animation —
///       genau der Grund, warum das X auf dem Gerät mehrere Tipps brauchte.
///       Die Lupe existiert in diesem Fenster noch gar nicht wieder als
///       Tippziel, ein echter Nutzer kann das nicht sein → verwerfen.
///     – Bei offenem Anlegen-Cover (oder im `coverSettle`-Fenster nach dessen
///       Zufahren) liegt die Lupe unter dem Cover bzw. unter der laufenden
///       Zoom-Animation — auch das kann kein Nutzer sein. Es ist der
///       Such-Rollen-Tab (der Anlegen-Kreis!), dessen Auswahl das System
///       verspätet doch noch als Such-Aktivierung ausspielt → verwerfen.
///  * `dismissed`: das Binding fällt auf `false` — ab jetzt läuft das
///    Schließ-Fenster.
///
/// Die Ansicht setzt ein „verworfen" um, indem sie das Binding sofort wieder
/// auf `false` schreibt (und den Fokus löscht) — dieselbe Klemme, die sich
/// beim Fokus bereits bewährt hat, jetzt auch für die Präsentation selbst.
struct SearchFlow {
    enum State: Equatable { case closed, open, closing(since: Date) }
    private(set) var state: State = .closed

    /// Länger als die Abklapp-Animation (~0,35 s), kürzer als der schnellste
    /// echte Wieder-Tipp auf die (erst danach wieder existierende) Lupe.
    static let closeSettle: TimeInterval = 0.45
    /// Zoom-Rückfahrt des Anlegen-Covers (~0,5 s) plus Luft für den
    /// nachzügelnden Such-Rollen-Impuls des Systems.
    static let coverSettle: TimeInterval = 0.8

    /// So lange muss das Zuklapp-Bild anhalten, bevor die App nachzieht
    /// (siehe `fieldReading`): lang genug, dass ein einzelnes Messbild nichts
    /// auslöst, kurz genug, dass „ein Tipp schließt" bleibt. Gemessen: das
    /// abgebrochene Zuklappen der iOS-27-Suche liegt rund 0,22 s unter der
    /// Ruhebreite — ein Fenster von 0,12 s liegt sicher darin.
    static let dismissSettle: TimeInterval = 0.12
    /// Ab so vielen Punkten UNTER der Ruhebreite gilt das Feld als
    /// zuklappend. Gemessen: Ruhe 344 pt, Zuklappen fällt sofort auf 280 pt;
    /// das Absenden über die Tastatur lässt die Breite exakt stehen.
    static let collapseMargin: CGFloat = 10

    private var coverOpen = false
    private var coverClosedAt: Date?
    /// Wurde das Feld seit DIESEM Öffnen überhaupt schon gemessen? Ohne diese
    /// Klemme schlösse der Beobachter die Suche im selben Atemzug wieder, in
    /// dem sie aufgeht — beim Aufklappen ist das Feld ein paar Bilder lang
    /// noch nicht da.
    private var fieldSeen = false
    /// Die Breite, die das Feld im RUHEZUSTAND hat (zuletzt gemessen, solange
    /// es die Eingabe hielt). Der Maßstab, an dem ein Zuklappen erkannt wird.
    private var restingWidth: CGFloat?
    /// Seit wann sieht die Messung nach Zuklappen aus? (nil = tut sie nicht)
    private var dismissSince: Date?
    /// Schon gemeldet? Ein Zuklappen ist EIN Ereignis, kein Dauerzustand —
    /// sonst feuerte der Takt zwanzigmal je Sekunde dieselbe Meldung.
    private var dismissReported = false

    /// Anlegen-Cover auf/zu — der Such-Rollen-Tab ist der Anlegen-Kreis,
    /// seine fehlgeleitete Such-Aktivierung hängt an genau diesem Fenster.
    mutating func coverChanged(open: Bool, now: Date = .now) {
        coverOpen = open
        if !open { coverClosedAt = now }
    }

    /// Programmatisches Öffnen — ausdrückliche Absicht, gilt immer.
    mutating func userOpened() { enterOpen() }

    /// JEDER Weg nach `open` läuft hier durch — und setzt die Feldmessung
    /// zurück. Das ist der Grund, warum der Beobachter über beliebig viele
    /// Zyklen gleich arbeitet: er trägt NICHTS aus dem vorigen Zyklus mit.
    /// (Ohne das reichte ein `fieldGoneSince` von vorhin, um die frisch
    /// geöffnete Suche im ersten Messschritt wieder zuzuschlagen.)
    private mutating func enterOpen() {
        state = .open
        resetField()
    }

    private mutating func resetField() {
        fieldSeen = false
        restingWidth = nil
        dismissSince = nil
        dismissReported = false
    }

    /// Das System hat präsentiert (Binding → `true`, nicht von uns).
    /// Ergebnis `false` = verwerfen (Binding sofort zurücksetzen).
    mutating func systemPresented(now: Date = .now) -> Bool {
        if case .open = state { return true }
        if case .closing(let since) = state,
           now.timeIntervalSince(since) < Self.closeSettle { return false }
        if coverOpen { return false }
        if let t = coverClosedAt,
           now.timeIntervalSince(t) < Self.coverSettle { return false }
        enterOpen()
        return true
    }

    /// Was der Feld-Beobachter gemessen hat. Rückgabe `true` = die Ansicht
    /// muss `isPresented` SELBST auf `false` ziehen.
    ///
    /// Das ist die Antwort auf den zweiten iOS-27-Fehler: das System klappt
    /// die Suche zu, schreibt aber kein `false` zurück (auch `\.isSearching`
    /// bleibt wahr — nachgemessen). Schlimmer noch: weil das Binding wahr
    /// bleibt, ZIEHT SwiftUI das halb zugeklappte Feld sofort wieder auf.
    /// Genau deshalb reicht „ist das Feld weg?" nicht — beim ersten Tipp ist
    /// es nie weg, es klappt nur an und wird zurückgerissen. Der Tipp muss
    /// IM ZUKLAPPEN erkannt werden, bevor das Zurückreißen einsetzt.
    ///
    /// Woran: an der BREITE des Feldes, gegen die Ruhebreite gehalten
    /// (Messwerte im Simulator, iOS 27.0, 17 Pro Max):
    ///
    /// | Vorgang            | Eingabe | Breite        |
    /// |--------------------|---------|---------------|
    /// | offen, in Ruhe     | ja      | 344 pt        |
    /// | Liste scrollen     | ja      | 344 pt        |
    /// | „Suchen" (Tastatur)| nein    | 344 pt        |
    /// | X getippt          | nein    | 344 → 280 pt  |
    ///
    /// Die Eingabe allein taugt also NICHT als Signal (das Absenden über die
    /// Tastatur gibt sie ebenso ab), die Breite allein auch nicht (beim
    /// Aufklappen schrumpft das Feld von 389 auf 344). Erst beides zusammen —
    /// „hält die Eingabe nicht mehr UND ist schmaler als in Ruhe" — trennt
    /// das Zuklappen sauber von allem anderen.
    ///
    /// Vier Eigenschaften, und alle vier sind Absicht:
    ///  * **Nur im Zustand `open`.** Sonst ist die Messung bedeutungslos und
    ///    wird zurückgesetzt — ein Beobachter, der über Zustandsgrenzen
    ///    hinweg etwas merkt, ist genau der, der beim zweiten Durchgang
    ///    danebengreift.
    ///  * **Erst sehen, dann vermissen** (`fieldSeen`): vor dem ersten
    ///    Treffer schließt nichts, sonst schlüge die Suche im selben Atemzug
    ///    wieder zu, in dem sie aufgeht.
    ///  * **Die Ruhebreite kommt aus DIESEM Öffnen**, nicht aus einer
    ///    Konstanten: sie hängt an Gerät, Sprache und daran, ob rechts ein X
    ///    steht.
    ///  * **Ereignislos wiederholbar.** Der Aufruf ist eine reine Frage; ihn
    ///    zwanzigmal je Sekunde zu stellen ändert nichts am Ergebnis, und ein
    ///    verschlucktes Messbild verschiebt es höchstens um einen Takt.
    mutating func fieldReading(_ reading: SearchFieldReading, now: Date = .now) -> Bool {
        guard case .open = state else {
            resetField()
            return false
        }
        if reading.present {
            fieldSeen = true
            // Ruhebreite nur, solange das Feld die Eingabe hält: während des
            // Zuklappens hat es sie schon abgegeben, seine Breite darf den
            // Maßstab also nicht mehr verschieben.
            if reading.focused {
                restingWidth = reading.width
                dismissSince = nil
                dismissReported = false
                return false
            }
        }
        guard fieldSeen else { return false }
        let dismissing: Bool
        if !reading.present {
            dismissing = true
        } else if let resting = restingWidth {
            dismissing = reading.width <= resting - Self.collapseMargin
        } else {
            // Feld da, ohne Eingabe, ohne je eine Ruhebreite gehabt zu haben:
            // daraus lässt sich nichts ablesen.
            dismissing = false
        }
        guard dismissing else {
            dismissSince = nil
            return false
        }
        guard !dismissReported else { return false }
        guard let since = dismissSince else {
            dismissSince = now
            return false
        }
        guard now.timeIntervalSince(since) >= Self.dismissSettle else { return false }
        dismissReported = true
        return true
    }

    /// Das Binding ist auf `false` gefallen (X, Abbrechen, eigener Rücksetzer).
    /// Nur aus `open` beginnt das Schließ-Fenster — ein verworfener
    /// Präsentations-Versuch (unser eigenes Zurückschreiben) startet keins.
    mutating func dismissed(now: Date = .now) {
        if case .open = state { state = .closing(since: now) }
    }
}

/// Referenz-Kiste fuer Scroll-Buchfuehrung ohne Observation.
final class ChromeScrollBox {
    var searchFlow = SearchFlow()
    /// Jüngste Oberkanten ALLER sichtbaren Zeilen (Messfühler-Index →
    /// minY im Listenraum) — reine Buchführung aus `handleScroll`, gelesen
    /// nur beim Öffnen der Nacharbeiten-Karte (`backfillAnchor`).
    var rowFrames: [Int: CGFloat] = [:]
}

/// Oberkanten aller sichtbaren Zeilen, Index -> minY im Listen-Koordinatenraum.
private struct RowOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { a, _ in a }
    }
}

// MARK: – Glas-Hüllen

/// Ein Stück Chrom-Glas. Ab iOS 26 ECHTES Liquid Glass (`glassEffect`,
/// interaktiv, im `GlassEffectContainer` mit stabiler `glassEffectID`, damit
/// Formen ineinander morphen können statt zu blenden); darunter die
/// Material-Attrappe, die es dort schon immer war.
private struct ChromeGlass: ViewModifier {
    enum Kind { case capsule, circle }

    let id: String
    let namespace: Namespace.ID
    let kind: Kind
    /// nil = neutrales Glas (Umschalter); gesetzt = eingefärbt (Anlegen).
    var accent: PaletteStyle?
    /// Teilen zwei Teile dieselbe Vereinigungs-Kennung, rechnet iOS ihr Glas
    /// als EINE Form — kein Steg, keine Taille, kein „halb drin, halb
    /// draußen". Verschiedene Kennungen = zwei getrennte Scheiben.
    var union: String
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch appearancePreferences.material {
        case .solid:
            solid(content)
        case .milky:
            material(content)
        case .liquid:
            if #available(iOS 26, *) {
                glass(content)
            } else {
                material(content)
            }
        case .adaptive:
            if #available(iOS 26, *) {
                glass(content)
            } else {
                material(content)
            }
        }
    }

    @ViewBuilder
    private func solid(_ content: Content) -> some View {
        switch kind {
        case .capsule:
            content
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
        case .circle:
            content
                .background(accent.map(Theme.accentFill)
                            ?? Color(.secondarySystemGroupedBackground), in: Circle())
        }
    }

    /// `.regular` (nie `.clear`) — das ist die Variante für Bedienelemente
    /// über beliebigem, scrollendem Inhalt. Für den neutralen Umschalter
    /// reicht sie über einem dicht gefüllten Raster trotzdem nicht: die
    /// Symbole standen im Habit-Text dahinter. Deshalb liegt ein
    /// SYSTEMHINTERGRUND mit halber Deckung als Tint darin — die kleinste
    /// Dosis, die alle drei Zeichen über einer voll gefüllten dunklen Karte
    /// lesbar macht, ohne dass das Glas zu Milchglas wird.
    @available(iOS 26, *)
    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        let style = Glass.regular.tint(glassTint).interactive()
        switch kind {
        case .capsule:
            content.glassEffect(style, in: .capsule)
                .glassEffectID(id, in: namespace)
                .glassEffectUnion(id: union, namespace: namespace)
        case .circle:
            content.glassEffect(style, in: .circle)
                .glassEffectID(id, in: namespace)
                .glassEffectUnion(id: union, namespace: namespace)
        }
    }

    private var glassTint: Color {
        if let accent {
            return Theme.accent(accent)
        } else if appearancePreferences.material == .adaptive {
            return Theme.color(Theme.adaptiveTintHex(preferences: appearancePreferences,
                                                     dark: colorScheme == .dark))
                .opacity(Theme.adaptiveSurfaceOpacity(preferences: appearancePreferences,
                                                       dark: colorScheme == .dark))
        } else {
            return Color(.systemBackground).opacity(0.5)
        }
    }

    /// Unter iOS 26 gibt es kein Glas, das ineinanderfließen könnte. Der
    /// `matchedGeometryEffect` besorgt wenigstens die Bewegung: der Knopf
    /// FÄHRT in die Leiste und verschwindet dort, statt in der Ecke
    /// auszublenden und links wieder aufzublitzen.
    @ViewBuilder
    private func material(_ content: Content) -> some View {
        switch kind {
        case .capsule:
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                .matchedGeometryEffect(id: id, in: namespace)
        case .circle:
            content
                .background(accent.map { Theme.accentFill($0) }
                            ?? Color(.secondarySystemGroupedBackground), in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

/// Schwebende Pillen über der Liste (Sync-Rückmeldung, Rückgängig-Toast):
/// dieselbe Materialwahl wie Karten und Einstellungen, damit die Rückmeldung
/// auf Solid, Milchglas, Liquid Glass und Auto nicht aus dem Design fällt.
private struct ToastSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .appSurface(cornerRadius: 999)
            .overlay(Capsule().strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}

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

/// Suchfeld, das NICHT dauerhaft sichtbar ist — NUR noch für iOS < 26.
///
/// Ab iOS 26 wohnt die Suche im echten Such-Tab (siehe `nativeShell`); dort
/// hängt ein gewöhnliches `.searchable` am Tab-Inhalt und das System
/// besorgt Auf- und Zuklappen unten an der Leiste. Der Feld-Beobachter für
/// den iOS-27-Binding-Fehler (Zuklappen schreibt kein `false` zurück; siehe
/// `SearchFieldProbe` und `SearchFlow.fieldReading`) bleibt daneben aktiv.
///
/// Vor iOS 26 bleibt der alte Umweg: `.searchable` erst anhängen, wenn die
/// Suche offen sein soll — `.minimize` gibt es dort nicht, und
/// `.navigationBarDrawer(displayMode: .automatic)` zeigte die Leiste am
/// Listenanfang dauerhaft. Das Anhängen mit `isPresented == true` klappt die
/// Leiste ohne Übergang auf (ein harter Schnitt, bewusst in Kauf genommen —
/// nur dort, wo das System nichts Besseres anbietet).
private struct LegacySearchDrawer: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let focus: FocusState<Bool>.Binding
    let prompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #unavailable(iOS 26), isPresented {
            let base = content
                .searchable(text: $text,
                            isPresented: $isPresented,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text(prompt))
            if #available(iOS 18, *) {
                base.searchFocused(focus)
            } else {
                base
            }
        } else {
            content
        }
    }
}

private extension View {
    func legacySearchDrawer(text: Binding<String>,
                            isPresented: Binding<Bool>,
                            focus: FocusState<Bool>.Binding,
                            prompt: String) -> some View {
        modifier(LegacySearchDrawer(text: text, isPresented: isPresented,
                                    focus: focus,
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

// MARK: – Der Feld-Beobachter (iOS 27)

/// Nimmt Messbilder des System-Suchfeldes auf und reicht jedes an
/// `onReading` weiter. Gebraucht wird das nur auf iOS 27 (siehe
/// `SearchableHidden`): dort klappt das System die Suche zu, ohne
/// `isPresented` zurückzuschreiben. Was ein Messbild bedeutet, entscheidet
/// nicht dieser Ausmesser, sondern `SearchFlow.fieldReading`.
///
/// **Warum getaktet und nicht ereignisgesteuert?** Zwei Gründe, beide
/// nachgemessen:
///  * Der naheliegende Weg — KVO auf `hidden`/`alpha`, wie beim Teller-Messer
///    der Tableiste — trägt nicht: beim Schließen wird das Feld nicht
///    versteckt, sondern ABGERÄUMT. Ein Beobachter hinge danach an einer
///    Ansicht, die es nicht mehr gibt, und der nächste Zyklus baute ein Feld
///    auf, das niemand beobachtet — genau die Bauart, bei der der ZWEITE
///    Durchgang stillsteht.
///  * Das entscheidende Signal ist ohnehin kein Ereignis, sondern eine
///    laufende Größe: die BREITE des Feldes im Zuklappen. Die liest man ab,
///    man bekommt sie nicht gemeldet.
///
/// Der Takt läuft ausschließlich bei OFFENER Suche (`active`) — im
/// Ruhezustand der App tickt hier nichts.
@available(iOS 26, *)
private struct SearchFieldWatcher: UIViewRepresentable {
    let active: Bool
    let onReading: (SearchFieldReading) -> Void

    func makeUIView(context: Context) -> UIView {
        let probe = SearchFieldProbe()
        probe.onReading = onReading
        probe.active = active
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let probe = uiView as? SearchFieldProbe else { return }
        probe.onReading = onReading
        probe.active = active
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        (uiView as? SearchFieldProbe)?.active = false
    }
}

@available(iOS 26, *)
private final class SearchFieldProbe: UIView {
    var onReading: ((SearchFieldReading) -> Void)?

    var active = false {
        didSet {
            guard active != oldValue else { return }
            if active { start() } else { stop() }
        }
    }

    /// 20 Hz: schnell genug, dass „ein Tipp schließt" sich sofort anfühlt
    /// (Messung + `dismissSettle` bleiben zusammen unter zwei Zehnteln) und
    /// dass das abgebrochene Zuklappen — rund 0,22 s schmal — nicht
    /// durchrutscht; langsam genug, dass ein paar Dutzend Ansichten je Takt
    /// nicht ins Gewicht fallen.
    private static let interval: TimeInterval = 0.05

    private var timer: Timer?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Fenster gewechselt: sofort neu messen, nicht erst im nächsten Takt.
        if active { sample() }
    }

    private func start() {
        stop()
        sample()
        // `.common`: sonst schweigt der Takt, solange ein Finger scrollt oder
        // eine Animation läuft — also genau in den Momenten, um die es geht.
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        onReading?(Self.reading(in: window))
    }

    /// Wie sieht das Suchfeld im Fenster gerade aus?
    ///
    /// Gesucht wird `UISearchTextField` — eine ÖFFENTLICHE Klasse (ab iOS 13);
    /// gelesen werden nur öffentliche Eigenschaften (`bounds`, `isHidden`,
    /// `alpha`, `isFirstResponder`). Nichts wird verändert, keine private
    /// Schnittstelle berührt.
    ///
    /// Die Breitenschwelle hält das AUFKLAPPEN aus der Messung heraus: das
    /// Feld wächst aus der Lupe heraus (nachgemessen: von unter 50 pt auf
    /// 344 pt in rund 0,25 s). Erst ab `minWidth` ist es ein Feld und nicht
    /// mehr eine wachsende Lupe — sonst geriete eine Zwischenbreite als
    /// „Ruhebreite" in die Bücher.
    static let minWidth: CGFloat = 120

    static func reading(in window: UIWindow?) -> SearchFieldReading {
        guard let window, let field = find(window, window: window) else { return .none }
        return SearchFieldReading(present: true,
                                  width: field.bounds.width,
                                  focused: field.isFirstResponder)
    }

    private static func find(_ view: UIView, window: UIWindow) -> UISearchTextField? {
        if let field = view as? UISearchTextField {
            let f = view.convert(view.bounds, to: window)
            if f.width >= minWidth, f.height >= 16, f.intersects(window.bounds) {
                return field
            }
        }
        // Unsichtbare Zweige gar nicht erst betreten: ein abgeblendeter
        // Navigationsbaum (verdeckt von einem Cover) zählt nicht als Feld.
        for sub in view.subviews where !sub.isHidden && sub.alpha > 0.05 {
            if let found = find(sub, window: window) { return found }
        }
        return nil
    }
}

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

    private func circle(diameter: CGFloat) -> some View {
        Button(action: action) {
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
        .buttonStyle(BubbleButtonStyle(reduceMotion: reduceMotion))
        .glassEffect(.regular.interactive(), in: .circle)
        .modifier(MoreZoomSource(id: zoomID, namespace: zoomNamespace))
        .accessibilityLabel(CreateAccessibility.label)
        .accessibilityIdentifier(CreateAccessibility.identifier)
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
