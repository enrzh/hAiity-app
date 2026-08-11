import SwiftUI
import UIKit
import AppIntents
import WidgetKit

/// Haupt-Einstieg. EIN Bereich (die Habit-Liste in ihrem NavigationStack).
///
/// „Mehr" wohnt NICHT mehr in der Leiste unten: es ist ein Punkt im
/// Drei-Punkte-Menü oben rechts und öffnet eine EIGENE SEITE
/// (`fullScreenCover`), die ab iOS 18 mit der Zoom-Transition aus genau
/// dieser Blase wächst und beim Schließen wieder in sie schrumpft — das X
/// oben LINKS schließt. Bildschirmartige Unterziele (Statistik, Archiv,
/// Über) bleiben Blätter, jetzt ÜBER der Mehr-Seite präsentiert.
///
/// Die Leiste unten ist ab iOS 26 die NATIVE TabView — mit genau einem
/// Inhalts-Tab (Habits) und einem zweiten Tab in der SUCH-ROLLE, dessen
/// abgesetzten runden Platz rechts der Anlegen-Knopf übernimmt: seine
/// Auswahl wird abgefangen (sofort zurück auf Habits) und öffnet die
/// Anlegen-SEITE — ein fullScreenCover, das ab iOS 18 aus genau diesem
/// Kreis zoomt (Anker: `createZoomAnchor`). Damit kommen Halten-Blase, Scroll-Minimieren
/// (`.tabBarMinimizeBehavior(.onScrollDown)`) und das geteilte Glas vom
/// SYSTEM, nicht aus einer Nachbildung. Die App-eigene Suche bleibt oben
/// rechts (plus Runterziehen) — am Such-Tab hängt bewusst KEIN
/// `.searchable`, es erscheint dort also nie ein Suchfeld.
///
/// Unter iOS 26 (17–25) bleibt die bisherige selbstgebaute Leiste als
/// Fallback: linksbündige Glas-Kapsel (nur noch „Habits") plus der + rechts
/// in der Ecke, mit dem gerechneten Zusammenziehen beim Scrollen.
struct ContentView: View {
    /// Auswahl der nativen Tableiste (iOS 26). `create` ist nie länger als
    /// einen Tick gewählt — die Auswahl wird abgefangen und öffnet das Blatt.
    enum NativeTab: Hashable { case habits, create }

    @State private var store = HabitStore()
    /// iCloud-Spiegel. Der lokale Stand in `store` ist die Wahrheit; das hier
    /// trägt ihn nur zur Apple-ID hinüber (siehe CloudSync).
    @State private var cloud = CloudSync()
    @State private var cloudStatus = CloudSyncStatus()
    /// Fasst schnelle Folgeänderungen zu EINEM Upload zusammen.
    @State private var pushes = PushDebouncer()
    @State private var editing: Habit?
    @State private var showAdd = false
    @State private var syncStatus = ""
    /// Auswahl der nativen Tableiste (iOS 26). Bleibt praktisch immer auf
    /// `.habits` — `.create` wird im selben Umlauf abgefangen.
    @State private var nativeTab: NativeTab = .habits
    /// Die Mehr-SEITE (fullScreenCover), geöffnet aus dem Menü oben rechts.
    @State private var showMore = false
    /// Bildschirmartige Unterziele des Mehr-Bereichs, als Blatt — präsentiert
    /// vom BILDSCHIRM (Menü-Direktwege, Deep-Links bei geschlossener
    /// Mehr-Seite). Die Mehr-Seite hat für ihre eigenen Zeilen eine eigene
    /// Route (`morePageRoute`): ein Blatt muss von der OBERSTEN Präsentation
    /// kommen, sonst erscheint es nicht.
    @State private var moreSheet: MoreRoute?
    /// Unterziel, aufgerufen aus einer Zeile DER MEHR-SEITE — als Blatt über
    /// dem Cover.
    @State private var morePageRoute: MoreRoute?
    /// Fährt der Anlegen-Knopf gerade? Solange ja, KEINE gemeinsame
    /// Glas-Vereinigung (siehe `chromeUnion`).
    @State private var chromeTravelling = false
    /// Auswahl der Statistik-Karten über dem Titel. Eigener kleiner Store
    /// (App-Group-Defaults), bewusst NICHT im HabitStore: die Auswahl ist
    /// eine Ansichts-Einstellung und soll weder Export noch iCloud anfassen.
    @State private var statsCards = StatsCardStore()
    @State private var search = ""
    /// Suchfeld ausgeklappt? Startet IMMER `false` — das Feld ist Standard
    /// unsichtbar und erscheint erst auf Tippen (bzw. per haiity://search).
    @State private var searching = false
    @FocusState private var searchFieldFocused: Bool
    /// Solange WAHR, arbeitet `.searchable` mit `.searchToolbarBehavior(.automatic)`
    /// statt `.minimize` — nötig für jede PROGRAMMATISCHE Präsentation
    /// (Such-Zug, Deep-Link): unter `.minimize` ignoriert das System das
    /// `isPresented`- wie das `searchFocused`-Binding vollständig (empirisch
    /// geprüft, auch verzögert). Zurück auf `.minimize` erst NACH dem
    /// Zuklappen (verzögert) — der Wechsel mitten in der Abklapp-Animation
    /// bricht sie ab und präsentiert das Feld erneut.
    @State private var searchNeedsAutomaticBehavior = false
    /// Sortiermodus. Früher ein `EditButton` in der Toolbar (zu breit), jetzt
    /// ein Punkt im Menü — der Modus muss deshalb selbst gehalten werden.
    @State private var editMode: EditMode = .inactive
    /// Scroll-Zustand der Habit-Liste, ausschließlich aus Zeilenpositionen
    /// abgeleitet (siehe ChromeScroll).
    ///
    /// **In einer Kiste, nicht als `@State`-Wert.** `decide` mutiert bei
    /// JEDER Messung (jede Zeilenbewegung, jedes Bild) — als Wert-`@State`
    /// invalidierte damit jedes Scroll-Bild den ganzen `ContentView.body`
    /// samt aller Karten und Raster (nachgemessen mit der Bildzeit-Sonde:
    /// 1–3 Bilder je Sekunde beim Scrollen). Die Kiste ist eine schlichte
    /// Referenz ohne Observation: Schreiben löst nichts aus. Was die
    /// Oberfläche wirklich braucht, ist allein die ENTSCHEIDUNG — und nur
    /// die steht als `@State` (`chromeCollapsed`) und flippt selten.
    @State private var chrome = ChromeScrollBox()
    /// Fortschritt des Such-Zugs (0…1) für den kleinen Spotlight-Hinweis.
    /// Beobachtbares Objekt statt `@State` — gelesen wird es AUSSCHLIESSLICH
    /// von `SearchPullIndicator`, damit ein laufender Zug nicht bei jedem
    /// Bildschritt diesen ganzen `body` neu auswertet (dieselbe Lehre wie
    /// beim Tafel-Zug, siehe `MorePanelProgress`).
    @State private var pullFeedback = SearchPullFeedback()
    /// Die eine Zahl, die aus dem Scroll-Signal an der Oberfläche ankommt.
    @State private var chromeCollapsed = false
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
    /// Namensraum der Zoom-Transition: die Mehr-Seite wächst aus dem
    /// Drei-Punkte-Menü oben rechts und schrumpft dorthin zurück (iOS 18+).
    @Namespace private var moreZoomNamespace
    /// Namensraum der Anlegen-Zoom-Transition: die Anlegen-Seite wächst aus
    /// dem Anlegen-Kreis der Leiste unten (iOS 18+).
    @Namespace private var createZoomNamespace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Zusammengezogenes Chrom (Fallback-Leiste) und verdichtete Karten.
    ///
    /// `!searching` ist kein Schönheitsdetail: das Aufklappen der Suche
    /// schiebt die Liste um gut 100 pt: die Zeilenmessung liest das als Wisch
    /// und zieht alle Köpfe zusammen, ohne dass jemand gescrollt hätte.
    private var collapsed: Bool { chromeCollapsed && !searching }

    private static let listSpace = "habit-list"

    /// Vereinigungs-Kennung der Glasteile unten. Teilen zwei Teile dieselbe,
    /// rechnet iOS ihr Glas als EINE Form: zusammengezogen werden Umschalter
    /// und Anlegen-Knopf zu einem Blob, sonst bleibt jeder eine eigene
    /// Scheibe an seinem Rand.
    ///
    /// **Erst am Ziel vereinigen.** `chromeTravelling` ist kein Feinschliff:
    /// iOS rechnet die Vereinigung aus den RUHENDEN Plätzen der Mitglieder.
    /// Trägt der Knopf die gemeinsame Kennung schon während der Fahrt, wird
    /// er auf die Blob-Form geschnitten und ist unterwegs schlicht nicht da
    /// — er verschwindet rechts und erscheint links. Genau die Blende, die
    /// wegsollte (nachgemessen an der Aufnahme). Während der Fahrt bleibt er
    /// deshalb eine eigene Scheibe, die sichtbar wandert; erst wenn sie
    /// steht, fließen beide zu einer Kapsel zusammen.
    ///
    /// Die Mehr-Tafel steht bewusst gar nicht in dieser Vereinigung.
    /// Ausprobiert und wieder ausgebaut: verschmilzt die Tafel mit der
    /// Kapsel, gewinnt die große Fläche — die Leiste verliert ihre eigene
    /// Form, und der Anlegen-Knopf steht blass auf dem Tafelglas. Der
    /// Eindruck „wächst aus der Leiste" trägt die Animation (Skalierung mit
    /// Anker auf dem Mehr-Segment), nicht ein gemeinsamer Glaskörper.
    private func chromeUnion(_ solo: String) -> String {
        collapsed && !chromeTravelling ? "chrome-blob" : solo
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
            // Die drei Zeilen sind das ganze Theming-Gerüst: das Schema wird
            // fürs FENSTER gesetzt (Blätter inklusive), die Palette reist als
            // Umgebungswert bis in jede Rasterzelle, und der Tint zieht die
            // System-Steuerelemente mit. Alle drei hängen am Store, damit ein
            // Umstellen in „Mehr" sofort durchschlägt.
            .preferredColorScheme(store.appearance.colorScheme)
            .environment(\.palettes, store.palettes)
            // accentText statt accent: die Markenfarbe hat auf hellem Grund
            // nur ~3,4:1 — als Schrift/Symbolfarbe ist das zu wenig.
            .tint(Theme.accentText(store.paletteStyle))
            .onOpenURL { handleDeepLink($0) }
            // Blätter sind eine EIGENE Präsentation: Farbe und Tint von oben
            // kommen dort nicht an (nachgemessen — die Farbwahl im Blatt zeigte
            // sonst Grün, während die App längst in einer eigenen Farbe lief).
            // Deshalb beides hier noch einmal, an EINER Stelle je Blatt.
            // ANLEGEN ist eine SEITE, kein Half-Sheet mehr — dasselbe Muster
            // wie „Mehr": ein fullScreenCover, das ab iOS 18 mit der
            // Zoom-Transition aus dem Anlegen-Kreis der Leiste wächst und
            // beim Schließen dorthin zurückschrumpft; X oben links schließt.
            .fullScreenCover(isPresented: $showAdd) { createPage }
            .sheet(item: $editing) {
                EditHabitSheet(store: store, existing: $0)
                    .themed(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            // Statistik, Archiv und Über sind SEITEN: eigener Titel, eigene
            // Navigationsleiste, beliebig lang. In der Tafel über der Leiste
            // hätten sie keinen Platz — als Blatt behalten sie ihre Form.
            .sheet(item: $moreSheet) { route in
                NavigationStack {
                    moreDestination(route)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(String(localized: "Fertig")) { moreSheet = nil }
                                    .accessibilityIdentifier("close-more-sheet")
                            }
                        }
                }
                .themed(store)
            }
            // Die Mehr-SEITE. Ein `fullScreenCover`, ab iOS 18 mit der
            // Zoom-Transition: sie wächst aus der Drei-Punkte-Blase oben
            // rechts und schrumpft beim Schließen dorthin zurück. Darunter
            // (iOS 17) eine schlichte Blende — dieselbe Seite, ohne Morph.
            .fullScreenCover(isPresented: $showMore) { morePage }
            .task {
                await boot()
                #if DEBUG
                handleLaunchScreenArgument()
                if FrameProbe.enabled { FrameProbe.shared.start() }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Widget-Intent kann data.json extern geändert haben —
                    // purer Re-Read (No-op bei unveränderter mtime).
                    store.reloadFromDisk()
                    // Konto kann sich ausserhalb der App geändert haben
                    // (an-/abgemeldet), und das andere Gerät kann gehakt
                    // haben, während diese App im Hintergrund lag.
                    cloudStatus.refresh()
                    Task { await rescheduleReminders() }
                    Task { await syncNow(announce: false) }
                }
            }
            .onChange(of: search) { _, q in
                // Sortieren und Filtern schließen sich aus: die Offsets aus
                // `onMove` zeigen sonst in eine Liste, die es nicht gibt.
                if !q.isEmpty { editMode = .inactive }
            }
            .onChange(of: showMore) { _, open in
                guard open else { return }
                editMode = .inactive
                expandChrome()
                // Ein Toast, der auf eine Karte zeigt, die man nicht mehr
                // sieht, ist nur noch ein Knopf ins Ungewisse.
                undo.clear()
                // Dasselbe für die Nacharbeiten-Karte: sie gehört zu einer
                // Zeile der Liste, und die ist gerade verdeckt worden.
                backfill = nil
            }
            .onChange(of: showAdd) { _, open in
                guard open else { return }
                // Dieselbe Hygiene wie beim Öffnen der Mehr-Seite: das Cover
                // verdeckt Liste, Toast und Karte vollständig.
                editMode = .inactive
                expandChrome()
                undo.clear()
                backfill = nil
            }
            .onChange(of: nativeTab) { _, tab in
                // Der Such-Rollen-Tab IST der Anlegen-Knopf: die Auswahl wird
                // sofort zurückgenommen und stattdessen das Blatt geöffnet.
                // Bei offener Nacharbeiten-Karte passiert BEWUSST nichts —
                // dieselbe Sperre wie `allowsHitTesting` an der
                // Fallback-Leiste.
                guard tab == .create else { return }
                nativeTab = .habits
                if backfill == nil { showAdd = true }
            }
            .onChange(of: searchFieldFocused) { _, focused in
                // Ein TRUE-Fokus bei GESCHLOSSENER Suche präsentiert unter
                // `.minimize` das Feld sofort wieder — genau der Kreislauf,
                // der das X mehrfach drücken ließ: das System schreibt beim
                // Abbrechen kurz `focus = true`, und je nach Reihenfolge
                // landet das NACH unserem Löschen. Hier hart klemmen: Fokus
                // gibt es nur bei offener Suche. (`openSearch` setzt
                // `searching` VOR dem Fokus, der legitime Weg bleibt frei.)
                if focused && !searching { searchFieldFocused = false }
            }
            .onChange(of: searching) { _, open in
                // Auf- und Zuklappen der Suche ist ein Layout-Sprung, kein
                // Scrollen — den Lauf verwerfen, sonst wirkt er hinterher nach.
                expandChrome()
                // Beim Schließen den Fokus AKTIV löschen: bleibt das
                // `searchFocused`-Binding wahr, präsentiert das System das
                // Feld nach dem Rückwechsel auf `.minimize` sofort wieder
                // (X → Lupe → Leiste klappt wieder auf).
                if !open {
                    searchFieldFocused = false
                    scheduleMinimizeReturn()
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
                Color(.systemGroupedBackground).ignoresSafeArea()
                habitsStack
            }
            // Über der Liste, unter dem Fallback-Chrom (das `body` DANACH
            // auflegt): der Rückgängig-Toast im Chrom-Stapel bleibt über der
            // offenen Karte antippbar.
            .overlay { backfillLayer }
        }
    }

    /// Die native Leiste, GETEILT wie die System-Apps mit Suche: der
    /// Habits-Tab als Pille links, der Such-Rollen-Tab als eigener Kreis
    /// rechts — nur dass der Kreis hier ANLEGEN heißt und ein Plus trägt.
    /// Halten-Blase, Minimieren beim Scrollen und das Glas kommen vom System.
    ///
    /// Am Such-Tab hängt KEIN `.searchable` — das System hat also nie ein
    /// Suchfeld, das es dort aufklappen könnte; die Auswahl wird in
    /// `onChange(of: nativeTab)` abgefangen, bevor der leere Inhalt sichtbar
    /// wird.
    @available(iOS 26, *)
    private var nativeShell: some View {
        TabView(selection: $nativeTab) {
            Tab(String(localized: "Habits"), systemImage: "square.grid.2x2",
                value: NativeTab.habits) {
                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                    habitsStack
                }
                // Die Nacharbeiten-Karte ÜBER der Liste, aber UNTER den
                // schwebenden Pillen: der Rückgängig-Toast ist das Zurück zu
                // genau dem, was die Karte gerade geschrieben hat, und muss
                // bei offener Karte antippbar bleiben — dieselbe Schichtung
                // wie im Fallback (Karte unter dem Chrom-Stapel).
                .overlay { backfillLayer }
                // Toast und Sync-Pille schweben über der Liste, oberhalb
                // der nativen Leiste (der Tab-Inhalt endet an deren
                // Sicherheitszone). Bei offener Suche stünden sie auf der
                // Tastatur — dann nicht.
                .overlay(alignment: .bottom) {
                    if !searching { floatingPills }
                }
            }
            Tab(String(localized: "Neuer Habit"), systemImage: "plus",
                value: NativeTab.create, role: .search) {
                // Nie sichtbar: die Auswahl wird im selben Umlauf
                // zurückgenommen (siehe onChange). Trotzdem kein leeres
                // Weiß, falls doch je ein Bild durchrutscht.
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Der unsichtbare Anker über dem System-Anlegen-Kreis — Quelle der
        // Zoom-Transition der Anlegen-Seite. Am TabView-Rahmen verankert
        // (der reicht bis zur Bildschirmkante, die Leiste liegt darin).
        .overlay(alignment: .bottomTrailing) { createZoomAnchor }
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

    // MARK: – Die Mehr-Seite

    /// Die Mehr-Seite: dieselbe Liste wie früher in der Tafel, jetzt als
    /// eigene Seite mit System-Navigationsleiste. Schließen über das X oben
    /// LINKS; die Unterziele (Statistik, Archiv, Über) öffnen als Blätter
    /// ÜBER dieser Seite (`morePageRoute`) — ein Blatt kann nur von der
    /// obersten Präsentation kommen.
    private var morePage: some View {
        NavigationStack {
            MoreView(store: store, cloudStatus: cloudStatus,
                     statsCards: statsCards, onOpen: { morePageRoute = $0 })
                .navigationTitle(String(localized: "Mehr"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showMore = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "Schließen"))
                        .accessibilityIdentifier("close-more")
                    }
                }
        }
        .sheet(item: $morePageRoute) { route in
            NavigationStack {
                moreDestination(route)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(String(localized: "Fertig")) { morePageRoute = nil }
                                .accessibilityIdentifier("close-more-sheet")
                        }
                    }
            }
            .themed(store)
        }
        .themed(store)
        .modifier(MoreZoomDestination(id: Self.moreZoomID, namespace: moreZoomNamespace))
        .accessibilityIdentifier("more-page")
    }

    /// Quelle und Ziel der Zoom-Transition tragen dieselbe Kennung.
    private static let moreZoomID = "more-blob"

    // MARK: – Die Anlegen-Seite

    /// Die Anlegen-Seite: dasselbe Formular wie bisher im Half-Sheet
    /// (EditHabitSheet bringt seinen eigenen NavigationStack samt
    /// Sichern-Knopf mit), jetzt als volle Seite mit X oben links
    /// (`asPage`). Ziel der Zoom-Transition: sie wächst aus dem
    /// Anlegen-Kreis der Leiste (siehe `createZoomAnchor` bzw. der
    /// Fallback-`addButton`) und schrumpft dorthin zurück.
    private var createPage: some View {
        EditHabitSheet(store: store, asPage: true)
            .themed(store)
            .modifier(MoreZoomDestination(id: Self.createZoomID,
                                          namespace: createZoomNamespace))
    }

    private static let createZoomID = "create-circle"

    /// Quelle der Anlegen-Zoom-Transition unter iOS 26 — Option (b):
    ///
    /// Der Anlegen-Kreis ist dort das SYSTEMGEZEICHNETE Such-Rollen-Element
    /// der nativen TabView; an ihm selbst gibt es keinen Modifier-Pfad für
    /// `matchedTransitionSource`. Deshalb liegt hier ein unsichtbarer,
    /// nicht treffbarer Anker exakt ÜBER dem Kreis — als Overlay am
    /// TabView-Rahmen (der bis zur Bildschirmkante reicht), unten rechts
    /// verankert und mit nachgemessenen Abständen positioniert.
    ///
    /// Der Kreis WANDERT beim Scroll-Minimieren (`.onScrollDown`): kleiner
    /// und näher an der Kante. Der Anker folgt über `collapsed` — dieselbe
    /// Scroll-Entscheidung, die auch die Karten verdichtet, läuft praktisch
    /// synchron mit dem System-Minimieren (beide feuern auf den ersten
    /// Zentimeter Abwärts-Scroll). Die Maße sind am Simulator nachgemessen
    /// (Geräte-Punkte, Abstand von rechter/unterer Kante).
    @available(iOS 26, *)
    private var createZoomAnchor: some View {
        let d: CGFloat = collapsed ? CreateAnchor.miniDiameter : CreateAnchor.diameter
        return Circle()
            // Praktisch unsichtbar, aber NICHT `.clear`: eine komplett
            // transparente Quelle wird vom Transitionssystem verworfen und
            // der Zoom fiele auf die Bildschirmmitte zurück (nachgemessen).
            .fill(Color(.systemBackground).opacity(0.02))
            .frame(width: d, height: d)
            .modifier(MoreZoomSource(id: Self.createZoomID,
                                     namespace: createZoomNamespace))
            .padding(.trailing, collapsed ? CreateAnchor.miniTrailing : CreateAnchor.trailing)
            .padding(.bottom, collapsed ? CreateAnchor.miniBottom : CreateAnchor.bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Nachgemessene Lage des System-Anlegen-Kreises (Geräte-Punkte,
    /// Abstand von rechter/unterer Bildschirmkante). Beim Minimieren
    /// schrumpft der Kreis um seinen MITTELPUNKT — der bleibt, wo er ist.
    private enum CreateAnchor {
        static let diameter: CGFloat = 61
        static let trailing: CGFloat = 21
        static let bottom: CGFloat = 21
        static let miniDiameter: CGFloat = 47
        static let miniTrailing: CGFloat = 28
        static let miniBottom: CGFloat = 28
    }

    @ViewBuilder
    private func moreDestination(_ route: MoreRoute) -> some View {
        switch route {
        case .stats: StatsView(store: store)
        case .archive: ArchiveView(store: store)
        case .about: AboutView()
        }
    }

    // MARK: – Habits-Bereich

    /// Suche programmatisch öffnen — der EINE Weg für alle Einstiege außer
    /// der System-Lupe (Such-Zug, Deep-Link, Fallback-Knopf).
    ///
    /// Ab iOS 26 reicht `isPresented = true` NICHT: mit
    /// `.searchToolbarBehavior(.minimize)` klappt das System die Leiste nur
    /// über seine eigene Lupe oder über den FOKUS auf. Deshalb erst den
    /// Zustand setzen, dann im nächsten Umlauf den Fokus — das Setzen beider
    /// im selben Umlauf verschluckt die Präsentation ebenfalls.
    private func openSearch() {
        searchNeedsAutomaticBehavior = true
        withAnimation { searching = true }
        searchFieldFocused = true
    }

    /// Nach JEDEM Schließen zurück zu `.minimize` — aber erst an einem
    /// sicheren Punkt: Suche zu, kein (auch kein nachzüglerischer) Fokus.
    ///
    /// Der alte Weg (fester 0.7-s-Timer, der bei `searching == true` einfach
    /// aufgab) hatte zwei Löcher, beide vom Gerät gemeldet („X mehrmals
    /// drücken"):
    ///  * Wer innerhalb der 0.7 s wieder öffnete, ließ `.automatic` für immer
    ///    stehen — die Leiste stand danach DAUERHAFT unter dem Titel, kein X
    ///    der Welt schloss sie noch.
    ///  * Fiel der Umschalter mitten in die Abklapp-Animation, riss er die
    ///    Leiste wieder auf.
    /// Deshalb: bei offener Suche nicht aufgeben, sondern SPÄTER erneut
    /// versuchen (das nächste Schließen findet so immer einen scharfen
    /// Rücksteller vor), bei hängendem Fokus erst den Fokus lösen, und der
    /// eigentliche Wechsel läuft ohne Animation — er ist reine Buchhaltung,
    /// nichts, das eine laufende System-Animation kapern darf.
    private func scheduleMinimizeReturn(attempt: Int = 0) {
        guard attempt < 8 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard searchNeedsAutomaticBehavior else { return }
            guard !searching, !searchFieldFocused else {
                scheduleMinimizeReturn(attempt: attempt + 1)
                return
            }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { searchNeedsAutomaticBehavior = false }
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
        if store.activeHabits.isEmpty {
            emptyState
                .navigationTitle("Habits")
                // Auch ohne Habits muss „Mehr" erreichbar sein — es wohnt
                // jetzt oben rechts, nicht mehr in der Leiste unten.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { listMenu }
                }
        } else {
            habitList
                // Der große Titel steht seit den Statistik-Karten IN der
                // Liste (`titleRow`) — nur so kann etwas ÜBER ihm scrollen.
                // Die Navigationsleiste bleibt (Suche, Blob), aber ohne
                // eigenen Titel: zwei „Habits" übereinander wären keins.
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.editMode, $editMode)
                .searchableHidden(text: $search,
                                  isPresented: $searching,
                                  focus: $searchFieldFocused,
                                  automaticBehavior: searchNeedsAutomaticBehavior,
                                  prompt: String(localized: "Habits durchsuchen"))
                .toolbar {
                    // Ab iOS 26 stellt `.searchToolbarBehavior(.minimize)`
                    // die Lupe selbst als nativen Eintrag — hier kommt nur
                    // noch das Menü dazu, das System gruppiert benachbarte
                    // Einträge zu einer Glas-Gruppe. Darunter bleibt der
                    // Doppelknopf mit eigener Kapsel.
                    if #available(iOS 26, *) {
                        ToolbarItem(placement: .topBarTrailing) { listMenu }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) { searchAndMenu }
                    }
                }
        }
    }

    private var habitList: some View {
        List {
            statsRow
            titleRow
            if filteredHabits.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(filteredHabits.enumerated()), id: \.element.id) { index, habit in
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
        // Runterziehen ÖFFNET die Suche — wie Spotlight auf dem Homescreen.
        // `simultaneousGesture`: das Scrollen der Liste läuft ungestört
        // weiter, die Geste liest nur mit. Entschieden wird rein aus
        // Fingerweg und Zeilenbewegung (SearchPull) — kein `@State` pro
        // Bild, die Zwischenstände liegen in der Chrom-Kiste.
        .simultaneousGesture(searchPullGesture)
        // Das Chrom liegt ÜBER der Liste. Ohne diese Boden-Marge endet der
        // scrollbare Inhalt genau darunter — auf schmalen Geräten und in den
        // Accessibility-Größen verdeckt es dann dauerhaft das Raster der
        // letzten Karte, und zwar in RTL genauso.
        .contentMargins(.bottom, chromeFootprint, for: .scrollContent)
        // Karten sind weiß/#1C1C1E, die Seite muss also die gruppierte
        // Fläche sein. Kein toolbarBackground-Override — die Navigations-
        // leiste behält ihr System-Glas.
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .coordinateSpace(.named(Self.listSpace))
        // Der Spotlight-Hinweis: eine kleine Lupe, die dem Finger beim
        // Runterziehen entgegenkommt — der Zug bekommt damit eine sichtbare
        // Antwort AB dem ersten Zentimeter, nicht erst beim Feuern.
        .overlay(alignment: .top) {
            SearchPullIndicator(feedback: pullFeedback,
                                accent: Theme.accentText(store.paletteStyle),
                                reduceMotion: reduceMotion)
        }
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

    /// Die Statistik-Karten ÜBER dem Titel — eine Listenzeile, die mit
    /// scrollt. Null aktive Karten: die Zeile existiert gar nicht (kein
    /// leerer Behälter). Der Schnappschuss ist memoisiert (StatsEngine):
    /// eine `body`-Auswertung kostet hier nur den Gleichheitsvergleich.
    @ViewBuilder
    private var statsRow: some View {
        if !statsCards.prefs.active.isEmpty {
            StatsCardsView(snapshot: StatsEngine.snapshot(habits: store.activeHabits),
                           cards: statsCards.prefs.active)
                .equatable()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Theme.Metrics.gap,
                                          leading: Theme.Metrics.gutter,
                                          bottom: 0,
                                          trailing: Theme.Metrics.gutter))
        }
    }

    /// Der große „Habits"-Titel als LISTENZEILE — die Navigationsleiste
    /// trägt keinen mehr (siehe `habitsScreen`), sonst könnten die Karten
    /// nicht darüber stehen. Trägt Messfühler 0: die Zeile ist immer da und
    /// damit der Anker für „oben ist offen" und den Such-Zug.
    private var titleRow: some View {
        Text(String(localized: "Habits"))
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .background(rowProbe(0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Theme.Metrics.gap,
                                      leading: Theme.Metrics.gutter,
                                      bottom: 2,
                                      trailing: Theme.Metrics.gutter))
            .accessibilityIdentifier("habits-title")
    }

    /// Der Such-Zug: ein Runterziehen am LISTENANFANG über die Schwelle
    /// öffnet die Suche mit Tastatur. Die Entscheidung trifft `SearchPull`
    /// aus zwei Größen: dem Fingerweg (aus der Geste) und der echten
    /// Zeilenbewegung (aus der Scroll-Messung, via Chrom-Kiste). Nur im
    /// Gummiband am Listenanfang bewegt sich der Inhalt deutlich LANGSAMER
    /// als der Finger — genau daran erkennt der Zug „oben und drübergezogen",
    /// ohne normales Scrollen zu kapern und ohne je einen `@State` pro Bild
    /// anzufassen.
    private var searchPullGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !searching, backfill == nil else { return }
                #if DEBUG
                FrameProbe.shared.mark("pull.ev")
                #endif
                if chrome.pull.update(translation: value.translation) {
                    #if DEBUG
                    FrameProbe.shared.mark("pull.fire")
                    #endif
                    // Gefeuert: der Hinweis hat seine Arbeit getan — er
                    // verschwindet im selben Moment, in dem die Suchleiste
                    // erscheint, statt unter ihr weiterzuleuchten.
                    pullFeedback.value = 0
                    openSearch()
                    Theme.Haptics.select()
                } else {
                    // Fortschritt an den kleinen Hinweis melden — wie beim
                    // Tafel-Zug NUR an ein beobachtbares Objekt, das allein
                    // die Hinweis-Ansicht liest. Dieser `body` bleibt bei
                    // jedem Bildschritt unangetastet.
                    pullFeedback.value = chrome.pull.progress
                }
            }
            .onEnded { _ in
                chrome.pull.ended()
                pullFeedback.value = 0
            }
    }

    private func row(for habit: Habit, index: Int) -> some View {
        #if DEBUG
        FrameProbe.shared.mark("row")
        #endif
        return HabitCard(
            habit: habit,
            collapsed: collapsed,
            onToggleDay: { toggleDay(habit, day: $0) },
            // Zellentipp: nur AUSWÄHLEN. Die Karte kommt sofort — hier ist
            // kein Menü, das erst zugehen müsste.
            onSelectDay: { openBackfill(habit, day: $0, afterMenu: false) },
            onBackfill: { openBackfill(habit, day: DayKey.today(), afterMenu: true) },
            onIncrement: { increment(habit) },
            onClear: { revert(habit) },
            onMarkDone: { markDone(habit) },
            onEdit: { editing = habit },
            onArchive: { store.archive(habit.id) },
            onAnswer: { answer(habit, yes: $0) }
        )
        // `.equatable()`: siehe HabitCard. Ohne das baut jeder Tafel-/Toast-
        // Umbau alle sichtbaren Karten neu — gemessen der halbe Ruckler.
        .equatable()
        .background(rowProbe(index))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        // NUR die Seitenränder. Die vertikalen Abstände sitzen in der Karte
        // selbst, weil sie sich beim Zusammenziehen mitverkleinern müssen —
        // ein `listRowInsets` springt dabei, ein Padding wird animiert.
        .listRowInsets(EdgeInsets(top: 0,
                                  leading: Theme.Metrics.gutter,
                                  bottom: 0,
                                  trailing: Theme.Metrics.gutter))
        // KEINE Wischgesten mehr — weder hier noch als Einstellung. Alle
        // Aktionen einer Zeile hängen am langen Druck (HabitCard): die
        // Vorschau zeigt das vergrößerte Raster, die Aktionen stehen
        // darunter und sind beschriftet. Ein Wisch war unsichtbar, an beiden
        // Kanten verschieden belegt und musste in „Mehr" erklärt werden.
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
        mutate(habit, day: DayKey.today()) { store.increment(habit.id) }
    }

    /// Heute beantworten (Habit-Art „Ja/Nein"). Läuft durch dieselbe Stelle
    /// wie jedes Abhaken — also mit exaktem Rückgängig, auch wenn die
    /// Antwort eine bestehende überschreibt.
    private func answer(_ habit: Habit, yes: Bool) {
        mutate(habit, day: DayKey.today()) { store.answer(habit.id, yes: yes) }
    }

    /// Wisch-„Erledigt": hakt AN, nie ab. Ein schon erledigtes Checkbox-
    /// Habit bleibt unangetastet (und bekommt keinen Toast, der nichts
    /// zurückzunehmen hätte) — zum Abhaken gibt es „Rückgängig".
    private func markDone(_ habit: Habit) {
        let today = DayKey.today()
        // `isDone` ist bei Ja/Nein die ANTWORT und nicht „es steht ein Wert
        // da" — ein verneinter Tag ist hier also offen und darf auf Ja
        // gedreht werden.
        if habit.kind != .quantity, habit.isDone(today) { return }
        mutate(habit, day: today) {
            switch habit.kind {
            case .quantity: store.increment(habit.id)
            case .yesNo:    store.setValue(habit.id, day: today, value: Habit.Answer.yes)
            case .checkbox: store.toggle(habit.id, day: today)
            }
        }
    }

    /// Heutigen Eintrag zurücknehmen — komplett, auch bei Mengen-Habits.
    /// Der Toast bringt den exakten Vorwert zurück.
    private func revert(_ habit: Habit) {
        let today = DayKey.today()
        guard store.value(habit.id, day: today) != nil else { return }
        mutate(habit, day: today) { store.clear(habit.id, day: today) }
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
        guard let index = filteredHabits.firstIndex(where: { $0.id == habit.id }),
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
        // Der Such-Zug braucht die Lage der Titelzeile (Messfühler 0) —
        // in die Kiste geschrieben, nie in einen `@State`: das ist reine
        // Buchführung und darf keinen `body` invalidieren.
        chrome.pull.latestFirst = frames[0]
        // Ebenfalls Buchführung: die Zeilenlagen für den Anker der
        // Nacharbeiten-Karte (siehe `backfillAnchor`).
        chrome.rowFrames = frames
        // Während die Mehr-Seite offen ist (oder gerade auf- oder zufährt),
        // entscheidet das Chrom NICHT: die Präsentation verschiebt die
        // Zeilen ohne Finger, und der Umbau las sich sonst als Wisch —
        // dieselbe Regel wie früher beim Bereichswechsel.
        // Gleiches gilt für die Anlegen-Seite: auch ihr Cover verschiebt die
        // Zeilen beim Auf- und Zufahren ohne Finger.
        guard !showMore, !showAdd else { chrome.scroll.rebase(frames); return }

        // Läuft gerade ein möglicher Such-Zug (Finger unten, Titelzeile beim
        // Aufsetzen sichtbar) — oder ist er eben erst losgelassen worden —,
        // trifft das Chrom KEINE Entscheidung. Genau das war Punkt 4 der
        // Rückmeldung: der Gummiband-Rückschnepper nach einem Zug las sich
        // als Wisch nach unten, die Leiste zog sich zusammen, und ERST DANN
        // erschien die Suche. `rebase` statt bloßem Überspringen: die
        // Messung bleibt frisch und der Lauf fängt danach bei null an.
        if chrome.pull.suppressesChrome() { chrome.scroll.rebase(frames); return }
        guard let want = chrome.scroll.decide(frames) else { return }
        if reduceMotion {
            chromeCollapsed = want
        } else {
            withAnimation(.snappy(duration: 0.26)) { chromeCollapsed = want }
            // Für die Dauer der Fahrt bleibt der Anlegen-Knopf ein eigenes
            // Glasstück (siehe chromeUnion). Etwas länger als die Animation,
            // damit die Vereinigung erst greift, wenn wirklich nichts mehr
            // wandert.
            chromeTravelling = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                chromeTravelling = false
            }
        }
        chrome.scroll.settle()
    }

    /// Ausklappen von außen (Bereichswechsel, Suche): Lauf verwerfen und die
    /// Entscheidung zurücksetzen. Das Setzen von `chromeCollapsed` auf einen
    /// unveränderten Wert invalidiert nichts.
    private func expandChrome() {
        chrome.scroll.expand()
        chromeCollapsed = false
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DemoGrid(palette: store.paletteStyle)
            Text(String(localized: "Noch keine Habits"))
                .font(.title3.bold())
            Text(String(localized: "Leg einen an und fang an, Quadrate zu füllen — jeder Tag, an dem du dranbleibst, färbt eine Zelle."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
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
        .background(Color(.systemGroupedBackground))
    }

    // MARK: – Toolbar: Lupe und Menü in EINEM Blob
    //
    // „Bearbeiten" war als Wort-Knopf fast ein Drittel der Leiste breit und
    // stand als zweite Blase neben der Lupe. Jetzt: ein Behälter, zwei
    // Symbole. Die Lupe klappt die Suche auf, die drei Punkte tragen alles,
    // was die LISTE betrifft (Sortieren, Archiv, Statistik) — die drei Punkte
    // AUF der Karte bleiben davon unberührt, die betreffen einen Habit.

    /// Die Menü-Einträge — EINE Quelle für beide Leisten-Varianten und den
    /// Leerzustand. Neu darin: „Mehr" — der Bereich ist aus der Leiste unten
    /// hierher gezogen und öffnet die eigene Seite.
    @ViewBuilder
    private var listMenuItems: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                editMode = editMode.isEditing ? .inactive : .active
            }
        } label: {
            Label(editMode.isEditing
                  ? String(localized: "Fertig")
                  : String(localized: "Reihenfolge ändern"),
                  systemImage: "arrow.up.arrow.down")
        }
        .disabled(!search.isEmpty || store.activeHabits.isEmpty)
        Divider()
        Button {
            moreSheet = .stats
        } label: {
            Label(String(localized: "Statistik"), systemImage: "chart.bar")
        }
        Button {
            moreSheet = .archive
        } label: {
            Label(String(localized: "Archiv"), systemImage: "archivebox")
        }
        Divider()
        Button {
            showMore = true
        } label: {
            Label(String(localized: "Mehr"), systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("open-more")
    }

    /// Das Drei-Punkte-Menü — zugleich die QUELLE der Zoom-Transition: die
    /// Mehr-Seite wächst aus genau dieser Blase und schrumpft dorthin zurück.
    private var listMenu: some View {
        Menu {
            listMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel(String(localized: "Weitere Aktionen"))
        }
        .accessibilityIdentifier("list-menu")
        .modifier(MoreZoomSource(id: Self.moreZoomID, namespace: moreZoomNamespace))
    }

    /// Fallback (iOS < 26): der Doppelknopf als EIN Blob mit eigener Kapsel —
    /// dort gruppiert das System nichts von selbst.
    private var searchAndMenu: some View {
        HStack(spacing: 0) {
            Button {
                openSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: Theme.Metrics.hit, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Habits durchsuchen"))
            .accessibilityIdentifier("open-search")

            Divider()
                .frame(height: 20)

            Menu {
                listMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: Theme.Metrics.hit, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Weitere Aktionen"))
            .accessibilityIdentifier("list-menu")
            .modifier(MoreZoomSource(id: Self.moreZoomID, namespace: moreZoomNamespace))
        }
        .foregroundStyle(Theme.accentText(store.paletteStyle))
        .modifier(ToolbarBlob())
    }

    // MARK: – Fallback-Chrom unten (iOS < 26): Habits-Pille links, + rechts

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

    /// Linksbündige Glas-Kapsel — nur noch EIN Ziel: „Habits". Der Bereich
    /// „Mehr" wohnt oben rechts im Menü; die Kapsel ist die Standort-Anzeige
    /// der Leiste (und behält ihre Kennungen für die Verifikation).
    ///
    /// **Konzentrik.** Die Auswahl-Lasur liegt IN der Kapsel, also ist ihr
    /// Radius exakt der äußere MINUS dem Rand:
    ///
    ///     äußere Kapsel  H = control = 52  ->  R = H/2 = 26
    ///     Rand           p = (control − hit)/2 = 4   (rundum gleich)
    ///     innere Kapsel  h = control − 2p = hit = 44  ->  r = h/2 = 22
    private var switcher: some View {
        habitsPill
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

    /// Das eine Ziel der Fallback-Leiste. Kein Knopf mehr — es gibt nichts
    /// mehr umzuschalten; die Lasur zeigt schlicht, wo man ist. Kennung
    /// bleibt `tab-habits`, damit die Verifikation ihren Anker behält.
    private var habitsPill: some View {
        HStack(spacing: 4) {
            glyph("square.grid.2x2")
            if !collapsed {
                Text(String(localized: "Habits"))
                    .font(.footnote.weight(.semibold))
                    .fixedSize()
            }
        }
        .padding(.horizontal, collapsed ? 0 : Theme.Metrics.gap)
        // Die Lasur IST die Fläche: `hit` hoch UND mindestens `hit` breit —
        // eine Kapsel mit Radius hit/2 = 22, also exakt (26 − 4),
        // konzentrisch zur Glaskapsel (siehe `switcher`).
        .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
        .background {
            Capsule().fill(Theme.accent(store.paletteStyle).opacity(0.18))
        }
        .foregroundStyle(Theme.accentText(store.paletteStyle))
        .accessibilityLabel(String(localized: "Habits"))
        .accessibilityAddTraits([.isSelected])
        .accessibilityIdentifier("tab-habits")
    }

    /// Der Anlegen-Knopf. EIN Knopf, EINE Größe (`Metrics.control`, dasselbe
    /// Maß wie die Höhe des Umschalters) — er wechselt beim Scrollen nur den
    /// Platz: rechts unten in der Ecke, zusammengezogen direkt links an der
    /// Kapsel. Beide Zustände tragen dieselbe `glassEffectID`, deshalb
    /// WANDERT ein Glasstück und fließt mit dem Umschalter zusammen, statt
    /// dass zwei verschieden große Knöpfe gegeneinander blenden.
    private var addButton: some View {
        Button {
            showAdd = true
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
        .accessibilityLabel(String(localized: "Habit hinzufügen"))
        .accessibilityIdentifier("add-habit")
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
                    .font(.subheadline)
                    .lineLimit(1)
                Divider().frame(height: 16)
                Button {
                    performUndo()
                } label: {
                    Text(String(localized: "Rückgängig"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText(store.paletteStyle))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("undo-action")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .modifier(GlassCapsule())
            .transition(reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("undo-toast")
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
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
                .font(.caption2)
                .padding(.horizontal, Theme.Metrics.cardPadding)
                .padding(.vertical, Theme.Metrics.gap)
                .modifier(GlassCapsule())
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("sync-status")
        }
    }

    // MARK: – Deep-Links (haiity://habits|more|stats|archive|search|new)

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "haiity" else { return }
        switch url.host ?? url.lastPathComponent {
        case "habits":
            showMore = false
            moreSheet = nil
        case "more", "sync":
            // "sync" landet ebenfalls auf der Mehr-Seite — die iCloud-Zeile
            // steht dort ganz oben. Steht die Seite schon offen, ist der
            // Link erfüllt.
            showMore = true
        case "stats", "archive":
            let route: MoreRoute = (url.host ?? url.lastPathComponent) == "stats"
                ? .stats : .archive
            // Ist die Mehr-Seite offen, gehört das Blatt IHR — ein Blatt
            // kann nur von der obersten Präsentation kommen.
            if showMore { morePageRoute = route } else { moreSheet = route }
        case "search":
            showMore = false
            moreSheet = nil
            openSearch()
        case "new":
            showAdd = true
        default:
            break
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
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count,
              let url = URL(string: "haiity://\(args[i + 1])") else { return }
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
        let live = HaiityEntry(date: .now, habits: store.activeHabits, palettes: store.palettes)
        let entry = live.habits.isEmpty ? HaiityEntry.demo : live

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
        guard let habit = store.activeHabits.first else { return }
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
        store.onChange = {
            schedulePush()
            Task { await rescheduleReminders() }
            // Habit-Namen können sich geändert haben -> Siri-Phrasen auffrischen.
            HaiityShortcuts.updateAppShortcutParameters()
        }
        await rescheduleReminders()
        await syncNow(announce: false)
    }

    /// Die beiden Zusammenfassungen neu stellen. Sie tragen ZAHLEN, also
    /// müssen sie nach jeder Änderung am Store neu gerechnet werden — genau
    /// dafür hängt das hier an `store.onChange` und am Aktivwerden.
    private func rescheduleReminders() async {
        let calendar = Calendar.current
        let today = DayKey.today(calendar: calendar)
        let daily = Reminders.dailySummaryPlan(
            minutes: store.summaryMinutes,
            status: store.dailyStatus(today, calendar: calendar),
            calendar: calendar)
        let weekly = Reminders.weeklySummaryPlan(
            minutes: store.weeklySummaryMinutes,
            weekday: store.weeklySummaryWeekday,
            status: store.weeklyStatus(today, calendar: calendar),
            calendar: calendar)
        await Reminders.reschedule(daily: daily, weekly: weekly)
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
            guard let payload = store.exportJSON() else { return }
            try await cloud.push(payload) { remote in
                // EIN Merge in dieser App — der aus dem Store.
                if let remote { await MainActor.run { store.merge(remote: remote) } }
                return await MainActor.run { store.exportJSON() ?? payload }
            }
            cloudStatus.noteSuccess()
            // BEWUSST keine Erfolgs-Pille („✓ in iCloud gesichert") mehr:
            // dass der Normalfall funktioniert, ist keine Nachricht — die
            // Pille meldete sich nach jedem Häkchen. Fehler blitzen weiterhin
            // auf (unten), und der Dauerzustand steht in „Mehr".
        } catch {
            cloudStatus.noteFailure(error)
            // Nur echte Fehler stören beim Abhaken; „offline“ steht in „Mehr“.
            if announce, !CloudSyncError.map(error).isTemporary {
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

/// Referenz-Kiste um `ChromeScroll` — bewusst OHNE Observation. Die Messung
/// mutiert bei jedem Bild; als `@State`-Wert war genau das die Invalidierung
/// des ganzen Bildschirms pro Scroll-Bild (siehe `ContentView.chrome`).
final class ChromeScrollBox {
    var scroll = ChromeScroll()
    var pull = SearchPull()
    /// Jüngste Oberkanten ALLER sichtbaren Zeilen (Messfühler-Index →
    /// minY im Listenraum) — reine Buchführung aus `handleScroll`, gelesen
    /// nur beim Öffnen der Nacharbeiten-Karte (`backfillAnchor`).
    var rowFrames: [Int: CGFloat] = [:]
}

/// „Runterziehen öffnet die Suche" — die reine Entscheidung, ohne SwiftUI.
///
/// Das Problem, das sie löst: aus Zeilenpositionen allein ist „über den
/// Listenanfang hinausgezogen" nicht von „nach oben gescrollt" zu
/// unterscheiden (beides bewegt Zeilen nach unten), und eine gelernte
/// Ruhelage verlernt jeder Layoutwechsel. Deshalb zwei Signale statt einem:
///
///  * der FINGERWEG aus der Ziehgeste (`translation`), und
///  * die echte ZEILENBEWEGUNG seit Beginn der Geste (Messfühler 0,
///    von `handleScroll` in `latestFirst` abgelegt).
///
/// Im Gummiband am Listenanfang folgt der Inhalt dem Finger nur gebremst
/// (~halbe Strecke, iOS-Rubberband); beim normalen Scrollen folgt er 1:1.
/// Gefeuert wird also genau dann, wenn der Finger DEUTLICH weiter ist als
/// die Zeilen — und die Titelzeile beim Aufsetzen überhaupt sichtbar war
/// (mitten in der Liste ist Messfühler 0 abgeräumt und `latestFirst` nil,
/// dann kann die Geste nie feuern). Einmal je Geste, danach verriegelt.
struct SearchPull {
    /// Jüngste Lage der Titelzeile — Buchführung aus `handleScroll`.
    var latestFirst: CGFloat?
    /// Wie weit der laufende Zug schon ist (0…1, Anteil an `minTranslation`).
    /// Nur ein Zug, der die Verhältnis-Prüfung besteht, zählt — normales
    /// Scrollen bleibt bei 0 und der Hinweis erscheint dort nie.
    private(set) var progress: CGFloat = 0

    private var tracking = false
    private var startFirst: CGFloat?
    private var fired = false
    /// Bis wann das Chrom nach einem Zug noch stillhält (siehe
    /// `suppressesChrome`): der Gummiband-Rückschnepper nach dem Loslassen
    /// braucht einen Wimpernschlag, und er ist KEIN Scrollen.
    private var graceUntil: Date?

    /// So weit muss der FINGER mindestens gezogen haben: eine bewusste
    /// Strecke, kein Wackler. Vorher 90 — auf dem Gerät fühlte sich das an
    /// wie „die Suche kommt zu spät"; 70 liegt bei Spotlight, und die
    /// Verhältnis-Prüfung unten hält Scrollen und Wischer weiterhin fern.
    static let minTranslation: CGFloat = 70
    /// Die Zeilen dürfen höchstens so viel vom Fingerweg mitgegangen sein.
    /// 1:1 (= 1,0) ist Scrollen; das Gummiband liegt bei ~0,5.
    static let maxRatio: CGFloat = 0.6
    /// … aber bewegt haben müssen sie sich schon: ein Zug, bei dem gar
    /// nichts mitkommt, ist keiner (z. B. wenn eine andere Geste gewann).
    static let minTravel: CGFloat = 12
    /// So lange nach dem Loslassen hält das Chrom noch still — die Zeit, die
    /// das Gummiband braucht, um an seine Ruhelage zurückzuschnappen.
    static let chromeGrace: TimeInterval = 0.4

    /// Zählt dieser Fingerstand als Zug am Listenanfang? Die drei Prüfungen
    /// in EINER Stelle, damit Feuern und Fortschritt dieselben sind:
    /// deutlich senkrecht, Anker vorhanden, Zeilen deutlich LANGSAMER als
    /// der Finger (Gummiband), aber nicht festgenagelt.
    private func qualifies(down: CGFloat, width: CGFloat,
                           start: CGFloat, current: CGFloat) -> Bool {
        guard down > 0, abs(width) < down / 2 else { return false }
        let travel = current - start
        return travel >= Self.minTravel && travel <= Self.maxRatio * down
    }

    /// Neuer Gestenstand. `true` genau EINMAL: im Moment des Auslösens.
    mutating func update(translation: CGSize, first: CGFloat?? = nil) -> Bool {
        // ERST den Anker setzen, DANN die frische Messung übernehmen — der
        // Startwert der Geste ist die Lage VOR dieser Bewegung.
        if !tracking {
            tracking = true
            startFirst = latestFirst
            fired = false
            progress = 0
        }
        if let first { latestFirst = first }
        guard !fired, let start = startFirst, let current = latestFirst else {
            progress = 0
            return false
        }
        let down = translation.height
        guard qualifies(down: down, width: translation.width,
                        start: start, current: current) else {
            progress = 0
            return false
        }
        progress = min(1, down / Self.minTranslation)
        guard down >= Self.minTranslation else { return false }
        fired = true
        return true
    }

    /// Muss das Chrom (Leiste unten, Zusammenzieh-Logik) gerade stillhalten?
    /// Ja, solange ein Finger unten ist, der ein Such-Zug SEIN KÖNNTE (die
    /// Titelzeile war beim Aufsetzen sichtbar) — und noch `chromeGrace` lang
    /// danach, weil der Rückschnepper des Gummibands sonst als Wisch gelesen
    /// wird und die Leiste sich mitten im Öffnen der Suche zusammenzieht.
    func suppressesChrome(now: Date = .now) -> Bool {
        if tracking, startFirst != nil { return true }
        if let graceUntil, now < graceUntil { return true }
        return false
    }

    /// Finger oben: alles zurück auf Anfang — die nächste Geste entscheidet
    /// wieder frisch. War es ein Kandidat, hält das Chrom noch kurz still.
    mutating func ended(now: Date = .now) {
        if tracking, startFirst != nil {
            graceUntil = now.addingTimeInterval(Self.chromeGrace)
        }
        tracking = false
        startFirst = nil
        fired = false
        progress = 0
    }
}

/// Fortschritt des Such-Zugs für den kleinen Hinweis — beobachtbar, damit
/// NUR die Hinweis-Ansicht daran hängt (dieselbe Konstruktion wie
/// `MorePanelProgress`: der Schreiber invalidiert nichts, was ihn nicht liest).
@Observable
final class SearchPullFeedback {
    /// 0 = kein Zug, 1 = Schwelle erreicht (die Suche öffnet).
    var value: CGFloat = 0
}

/// Die kleine Lupe, die dem Such-Zug entgegenkommt — wie der
/// Spotlight-Hinweis auf dem Homescreen: sie fährt mit dem Finger herein,
/// wird zur Schwelle hin kräftiger und verschwindet im Moment des Öffnens.
/// Reine Rückmeldung: nicht treffbar, nicht vorlesbar.
private struct SearchPullIndicator: View {
    let feedback: SearchPullFeedback
    let accent: Color
    let reduceMotion: Bool

    var body: some View {
        let p = min(1, max(0, feedback.value))
        if p > 0.02 {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.quaternary))
                // Bewegung reduzieren: nur einblenden, nicht fahren.
                .offset(y: reduceMotion ? 12 : -28 + 46 * p)
                .opacity(0.35 + 0.65 * p)
                .scaleEffect(reduceMotion ? 1 : 0.7 + 0.3 * p)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Oberkanten aller sichtbaren Zeilen, Index -> minY im Listen-Koordinatenraum.
private struct RowOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { a, _ in a }
    }
}

/// Der selbstgebaute Ersatz für `.tabBarMinimizeBehavior(.onScrollDown)`.
///
/// Gerechnet wird ausschließlich mit Zeilenpositionen, weil das die einzige
/// Größe ist, die eine faule `List` unter iOS 17 hergibt. Drei Feinheiten,
/// ohne die es kippt:
///
///  * **Delta statt Absolutwert.** Zwischen zwei Momentaufnahmen wandern ALLE
///    sichtbaren Zeilen um denselben Betrag; die oberste gemeinsame Zeile
///    liefert ihn exakt, auch wenn Zeilen unterschiedlich hoch sind.
///  * **Nachlaufsperre.** Das Zusammenziehen ändert die Kopfhöhen und damit
///    die Zeilenpositionen — ohne kurze Sperre liest sich der eigene Umbau
///    als weiteres Scrollen und der Umschalter flackert.
///  * **Oben ist immer offen.** Solange die erste Zeile an ihrer Ruheposition
///    steht, bleibt das Chrom ausgeklappt; sonst bliebe es nach einem kurzen
///    Wisch am Listenanfang zusammengezogen stehen.
struct ChromeScroll {
    var collapsed = false

    private var frames: [Int: CGFloat] = [:]
    /// Ruheposition der ersten Zeile (größte je gesehene Oberkante).
    private var restY: CGFloat = -.greatestFiniteMagnitude
    /// Zurückgelegte Strecke seit dem letzten Richtungswechsel.
    private var run: CGFloat = 0
    private var settledUntil: Date?

    /// Ab hier gilt eine Bewegung als Absicht, nicht als Zittern.
    private static let threshold: CGFloat = 26
    /// So weit darf die Liste am Anfang stehen und gilt noch als „oben".
    private static let topSlack: CGFloat = 8
    /// Sprünge größer als das sind Layout-Wechsel (Bereich, Tastatur), kein Finger.
    private static let jumpLimit: CGFloat = 400

    /// Neue Messung einwerfen. Ergebnis: gewünschter Zustand, oder `nil`,
    /// wenn sich nichts ändert.
    mutating func decide(_ next: [Int: CGFloat], now: Date = .now) -> Bool? {
        let previous = frames
        frames = next
        if let first = next[0] { restY = max(restY, first) }
        if let settledUntil, now < settledUntil { return nil }

        // Oben angekommen: immer ausgeklappt, egal was der Lauf sagt.
        if let first = next[0], first > restY - Self.topSlack {
            run = 0
            return collapsed ? false : nil
        }

        guard let key = previous.keys
                .filter({ next[$0] != nil })
                .min(by: { previous[$0] ?? 0 < previous[$1] ?? 0 }),
              let before = previous[key], let after = next[key] else { return nil }
        let delta = after - before          // > 0: Inhalt wandert nach unten = hochgescrollt
        guard abs(delta) > 0.5, abs(delta) < Self.jumpLimit else { return nil }
        run = (delta < 0) == (run < 0) ? run + delta : delta

        if run <= -Self.threshold, !collapsed { return true }
        if run >= Self.threshold, collapsed { return false }
        return nil
    }

    /// Nach einem Wechsel kurz nicht hinhören (siehe Nachlaufsperre).
    mutating func settle(now: Date = .now) {
        settledUntil = now.addingTimeInterval(0.45)
        run = 0
    }

    /// Messung übernehmen, ohne zu entscheiden (anderer Bereich sichtbar).
    mutating func rebase(_ next: [Int: CGFloat]) {
        frames = next
        run = 0
    }

    mutating func expand() {
        collapsed = false
        run = 0
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

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            glass(content)
        } else {
            material(content)
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
        let style: Glass = accent.map { Glass.regular.tint(Theme.accent($0)).interactive() }
            ?? Glass.regular.tint(Color(.systemBackground).opacity(0.5)).interactive()
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
                .background(accent.map { Theme.accentFill($0) } ?? Color.clear, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

/// Schwebende Pillen über der Liste (Sync-Rückmeldung, Rückgängig-Toast):
/// kein Morphing, nur eine Fläche — aber dieselbe Lesbarkeits-Dosis wie das
/// Chrom. `.regular` allein reicht über einem voll gefüllten Raster oder
/// einer grünen Erledigt-Pille nicht: der Text darauf verschwimmt mit dem,
/// was durchscheint. Der Systemhintergrund mit halber Deckung als Tint ist
/// die kleinste Menge, die das behebt, ohne aus Glas Milchglas zu machen
/// (dieselbe Rechnung wie in `ChromeGlass`).
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(Color(.systemBackground).opacity(0.5)), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        }
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

/// Der Toolbar-Blob. Ab iOS 26 legt das System seine Glasfläche selbst unter
/// den Inhalt EINES Toolbar-Eintrags — deshalb dort nichts eigenes, sonst
/// liegt Glas auf Glas. Darunter ist die Leiste flach, da braucht der
/// Doppelknopf eine eigene Kapsel, damit er als ein Ding liest.
private struct ToolbarBlob: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }
}

/// Suchfeld, das NICHT dauerhaft sichtbar ist.
///
/// Ab iOS 26 macht das ganz das System: `.searchable` hängt DAUERHAFT am
/// Baum, `.searchToolbarBehavior(.minimize)` faltet es zu einer nativen Lupe
/// oben rechts zusammen. Auf- und Zuklappen laufen damit mit den
/// Systemkurven im Leisten-Glas — der frühere Einwand („zweite Lupe neben
/// dem Blob") ist hinfällig, seit die eigene Toolbar-Lupe entfällt und das
/// System seine Lupe mit dem Menü daneben selbst zur Glas-Gruppe gruppiert.
/// Beide Wege (Lupe, Such-Zug) schalten weiter nur `isPresented`.
///
/// Vor iOS 26 bleibt der alte Umweg: `.searchable` erst anhängen, wenn die
/// Suche offen sein soll — `.minimize` gibt es dort nicht, und
/// `.navigationBarDrawer(displayMode: .automatic)` zeigte die Leiste am
/// Listenanfang dauerhaft. Das Anhängen mit `isPresented == true` klappt die
/// Leiste ohne Übergang auf (ein harter Schnitt, bewusst in Kauf genommen —
/// nur dort, wo das System nichts Besseres anbietet).
private struct SearchableHidden: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let focus: FocusState<Bool>.Binding
    let automaticBehavior: Bool
    let prompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // `.minimize` nur im RUHEZUSTAND: es liefert die native Lupe samt
            // System-Aufklapp-Animation, verschluckt aber JEDE programmatische
            // Präsentation (isPresented wie searchFocused, auch verzögert —
            // empirisch geprüft). Der Such-Zug und der Deep-Link setzen
            // deshalb `isPresented` und der Modifier wechselt im selben
            // Umlauf auf `.automatic`, wo das Binding normal präsentiert.
            content
                .searchable(text: $text,
                            isPresented: $isPresented,
                            prompt: Text(prompt))
                .searchToolbarBehavior(automaticBehavior ? .automatic : .minimize)
                .searchFocused(focus)
        } else if isPresented {
            let base = content
                .searchable(text: $text,
                            isPresented: $isPresented,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text(prompt))
            // searchFocused gibt es erst ab iOS 18; darunter reicht der
            // isPresented-Binding.
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
    func searchableHidden(text: Binding<String>,
                          isPresented: Binding<Bool>,
                          focus: FocusState<Bool>.Binding,
                          automaticBehavior: Bool,
                          prompt: String) -> some View {
        modifier(SearchableHidden(text: text, isPresented: isPresented,
                                  focus: focus,
                                  automaticBehavior: automaticBehavior,
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

/// Deko fürs Empty-State: ein kleines zufälliges Contribution-Muster.
private struct DemoGrid: View {
    let palette: PaletteStyle
    @Environment(\.colorScheme) private var scheme
    private let pattern: [Int] = (0..<48).map { _ in
        Bool.random() && Bool.random() ? Int.random(in: 1...4) : 0
    }

    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(14), spacing: 3), count: 12)
        LazyVGrid(columns: cols, spacing: 3) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.level(level, dark: scheme == .dark, palette: palette))
                    .frame(height: 14)
            }
        }
        .frame(width: 12 * 17)
        .accessibilityHidden(true)
    }
}
