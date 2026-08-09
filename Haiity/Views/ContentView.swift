import SwiftUI
import AppIntents
import WidgetKit

/// Haupt-Einstieg. Zwei Bereiche (Habits / Mehr), jeder in eigenem
/// NavigationStack, umgeschaltet von einem EIGENEN Umschalter unten LINKS —
/// nicht von einer TabView.
///
/// Warum keine `TabView` mehr: die native Leiste zentriert sich, ab iOS 26
/// als schwebende Glas-Pille in der Mitte. Ein linksbündiger Platz ist dafür
/// nicht vorgesehen (kein Alignment-Knopf, kein Anker), und der Anlegen-Knopf
/// müsste weiter darüber schweben statt in der Ecke zu sitzen. Der Umschalter
/// ist deshalb selbst gebaut: linksbündige Glas-Kapsel, der + rechts unten in
/// der Ecke auf DERSELBEN Grundlinie. Beim Scrollen ziehen sich beide zu
/// EINEM kleinen Blob links zusammen (der + klappt in die Kapsel) — dieselbe
/// Idee wie `.tabBarMinimizeBehavior(.onScrollDown)`, nur selbst gerechnet,
/// damit sie auch unter iOS 26 und an der linken Kante funktioniert.
struct ContentView: View {
    /// Bewusst NICHT `Tab` — der Name gehört ab iOS 18 SwiftUI.
    enum Screen: Hashable { case habits, more }

    @State private var store = HabitStore()
    @State private var sync = GitHubSync()
    @State private var connectedLogin: String?
    @State private var editing: Habit?
    @State private var showAdd = false
    @State private var syncStatus = ""
    @State private var pushTask: Task<Void, Never>?
    @State private var screen: Screen = .habits
    @State private var search = ""
    /// Suchfeld ausgeklappt? Startet IMMER `false` — das Feld ist Standard
    /// unsichtbar und erscheint erst auf Tippen (bzw. per haiity://search).
    @State private var searching = false
    @FocusState private var searchFieldFocused: Bool
    @State private var morePath = NavigationPath()
    /// Sortiermodus. Früher ein `EditButton` in der Toolbar (zu breit), jetzt
    /// ein Punkt im Menü — der Modus muss deshalb selbst gehalten werden.
    @State private var editMode: EditMode = .inactive
    /// Scroll-Zustand der Habit-Liste, ausschließlich aus Zeilenpositionen
    /// abgeleitet (siehe ChromeScroll).
    @State private var chrome = ChromeScroll()
    /// Hält die Glasteile unten zusammen: gleiche ID vor und nach dem
    /// Zusammenziehen = ein Morph statt zweier Blenden.
    @Namespace private var glassNamespace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Zusammengezogenes Chrom gilt nur im Habits-Bereich; „Mehr" hat keine
    /// Karten und damit auch kein Scroll-Signal.
    ///
    /// `!searching` ist kein Schönheitsdetail: das Aufklappen der Suche
    /// schiebt die Liste um gut 100 pt: die Zeilenmessung liest das als Wisch
    /// und zieht alle Köpfe zusammen, ohne dass jemand gescrollt hätte.
    private var collapsed: Bool { chrome.collapsed && screen == .habits && !searching }

    private static let listSpace = "habit-list"

    /// Vereinigungs-Kennung der Glasteile unten. Zusammengezogen tragen
    /// Umschalter UND Anlegen-Knopf DIESELBE — iOS rechnet ihr Glas dann als
    /// eine einzige Form, der Knopf wird also aufgenommen statt daneben zu
    /// kleben. Ausgeklappt bekommt jeder seine eigene, damit die beiden
    /// getrennte Scheiben an den beiden Rändern bleiben.
    private func chromeUnion(_ solo: String) -> String { collapsed ? "chrome-blob" : solo }

    var body: some View {
        screens
            // Chrom liegt ÜBER den Bereichen, nicht in ihnen: so bleibt es
            // beim Umschalten stehen und die Listen scrollen darunter durch.
            .overlay(alignment: .bottom) { bottomChrome }
            // Die drei Zeilen sind das ganze Theming-Gerüst: das Schema wird
            // fürs FENSTER gesetzt (Blätter inklusive), die Palette reist als
            // Umgebungswert bis in jede Rasterzelle, und der Tint zieht die
            // System-Steuerelemente mit. Alle drei hängen am Store, damit ein
            // Umstellen in „Mehr" sofort durchschlägt.
            .preferredColorScheme(store.appearance.colorScheme)
            .environment(\.graphPalette, store.palette)
            // accentText statt accent: die Markenfarbe hat auf hellem Grund
            // nur ~3,4:1 — als Schrift/Symbolfarbe ist das zu wenig.
            .tint(Theme.accentText(store.palette))
            .onOpenURL { handleDeepLink($0) }
            .sheet(isPresented: $showAdd) {
                EditHabitSheet(store: store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $editing) {
                EditHabitSheet(store: store, existing: $0)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                await boot()
                #if DEBUG
                handleLaunchScreenArgument()
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Widget-Intent kann data.json extern geändert haben —
                    // purer Re-Read (No-op bei unveränderter mtime).
                    store.reloadFromDisk()
                    Task { await rescheduleReminders() }
                }
            }
            .onChange(of: search) { _, q in
                // Sortieren und Filtern schließen sich aus: die Offsets aus
                // `onMove` zeigen sonst in eine Liste, die es nicht gibt.
                if !q.isEmpty { editMode = .inactive }
            }
            .onChange(of: screen) { _, _ in
                editMode = .inactive
                chrome.expand()
            }
            .onChange(of: searching) { _, _ in
                // Auf- und Zuklappen der Suche ist ein Layout-Sprung, kein
                // Scrollen — den Lauf verwerfen, sonst wirkt er hinterher nach.
                chrome.expand()
            }
    }

    // MARK: – Bereiche

    /// Beide Stapel bleiben am Leben (Opacity statt `if`), damit Scroll- und
    /// Navigationszustand das Umschalten überleben — genau das, was die
    /// TabView vorher umsonst mitgebracht hat.
    private var screens: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            habitsStack
                .opacity(screen == .habits ? 1 : 0)
                .allowsHitTesting(screen == .habits)
                .accessibilityHidden(screen != .habits)
            moreStack
                .opacity(screen == .more ? 1 : 0)
                .allowsHitTesting(screen == .more)
                .accessibilityHidden(screen != .more)
        }
    }

    private var habitsStack: some View {
        NavigationStack {
            habitsScreen
        }
    }

    private var moreStack: some View {
        NavigationStack(path: $morePath) {
            MoreView(store: store, sync: sync, connectedLogin: $connectedLogin)
                .navigationTitle(String(localized: "Mehr"))
                .navigationDestination(for: MoreRoute.self) { route in
                    switch route {
                    case .stats: StatsView(store: store)
                    case .archive: ArchiveView(store: store)
                    case .about: AboutView()
                    }
                }
        }
        // Der Umschalter schwebt auch hier über der Liste — ohne Marge endet
        // die letzte Zeile darunter.
        .contentMargins(.bottom, chromeFootprint, for: .scrollContent)
    }

    // MARK: – Habits-Bereich

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
        } else {
            habitList
                .navigationTitle("Habits")
                .environment(\.editMode, $editMode)
                .searchableHidden(text: $search,
                                  isPresented: $searching,
                                  focus: $searchFieldFocused,
                                  prompt: String(localized: "Habits durchsuchen"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { searchAndMenu }
                }
        }
    }

    private var habitList: some View {
        List {
            if filteredHabits.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(filteredHabits.enumerated()), id: \.element.id) { index, habit in
                    row(for: habit, index: index)
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
        .background(Color(.systemGroupedBackground))
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
        Theme.Metrics.control + Theme.Metrics.gap + Theme.Metrics.gutter
    }

    private func row(for habit: Habit, index: Int) -> some View {
        HabitCard(
            habit: habit,
            collapsed: collapsed,
            onToggleDay: { store.toggle(habit.id, day: $0) },
            onIncrement: { store.increment(habit.id) },
            onClear: { store.clear(habit.id) },
            onEdit: { editing = habit },
            onArchive: { store.archive(habit.id) }
        )
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                store.archive(habit.id)
            } label: {
                Label(String(localized: "Archivieren"), systemImage: "archivebox")
            }
            .tint(.orange)
        }
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
        guard screen == .habits else { chrome.rebase(frames); return }
        guard let want = chrome.decide(frames) else { return }
        if reduceMotion {
            chrome.collapsed = want
        } else {
            withAnimation(.snappy(duration: 0.26)) { chrome.collapsed = want }
        }
        chrome.settle()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DemoGrid(palette: store.palette)
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
                    .background(Theme.accentFill(store.palette), in: Capsule())
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

    private var searchAndMenu: some View {
        HStack(spacing: 0) {
            Button {
                searching = true
                searchFieldFocused = true
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
                .disabled(!search.isEmpty)
                Divider()
                Button {
                    screen = .more
                    morePath = NavigationPath([MoreRoute.stats])
                } label: {
                    Label(String(localized: "Statistik"), systemImage: "chart.bar")
                }
                Button {
                    screen = .more
                    morePath = NavigationPath([MoreRoute.archive])
                } label: {
                    Label(String(localized: "Archiv"), systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: Theme.Metrics.hit, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Weitere Aktionen"))
            .accessibilityIdentifier("list-menu")
        }
        .foregroundStyle(Theme.accentText(store.palette))
        .modifier(ToolbarBlob())
    }

    // MARK: – Chrom unten: Umschalter links, + in der rechten Ecke

    @ViewBuilder
    private var bottomChrome: some View {
        // Bei offener Suche steht das Chrom sonst auf der Tastatur.
        if !searching {
            VStack(spacing: Theme.Metrics.gap) {
                syncBadge
                chromeRow
            }
            // Gleicher Seitenrand links wie rechts — der Umschalter steht
            // exakt so weit von der Kante wie der Anlegen-Knopf.
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, Theme.Metrics.gap)
        }
    }

    /// EIN Behälter für alle Glasteile unten. Ohne ihn rechnet jedes Stück
    /// sein Glas für sich und sie bleiben zwei Scheiben nebeneinander; erst
    /// im Container fließen zwei Formen, die näher beieinanderstehen als
    /// `spacing`, zu EINER Fläche zusammen. Genau das ist „zu einem kleinen
    /// Blob zusammenziehen": der + behält beim Einklappen seine Identität
    /// (`glassEffectID`), wandert aus der Ecke an die Kapsel und verschmilzt
    /// mit ihr — ein echter Glas-Morph, kein Aus- und Einblenden.
    @ViewBuilder
    private var chromeRow: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 20) { chromeStack }
        } else {
            chromeStack
        }
    }

    /// EINE Grundlinie: alle Kinder sind `Metrics.control` hoch, damit sitzen
    /// Ober- UND Unterkante von Umschalter und Anlegen-Knopf auf demselben
    /// Strich — unabhängig davon, ob der Knopf gerade rechts in der Ecke oder
    /// links am Blob klebt.
    private var chromeStack: some View {
        HStack(alignment: .center, spacing: 0) {
            switcher
            if collapsed {
                // Kein Abstand und dieselbe Vereinigungs-Kennung wie die
                // Kapsel: der Knopf wird von ihr AUFGENOMMEN, statt als
                // eigene Scheibe daneben stehen zu bleiben.
                addButton.padding(.leading, -Theme.Metrics.gap)
            }
            Spacer(minLength: 0)
            if !collapsed { addButton }
        }
        .frame(height: Theme.Metrics.control)
    }

    /// Linksbündige Glas-Kapsel mit beiden Bereichen. Zusammengezogen fallen
    /// die Beschriftungen weg — beide Ziele bleiben aber Knöpfe (und ihre
    /// Identifier im Baum), der Blob ist kein totes Abzeichen.
    private var switcher: some View {
        HStack(spacing: 4) {
            tabButton(.habits, symbol: "square.grid.2x2",
                      title: String(localized: "Habits"), id: "tab-habits")
            tabButton(.more, symbol: "ellipsis",
                      title: String(localized: "Mehr"), id: "tab-more")
        }
        // 44 (Trefferfläche) + 2 x 4 = 52 = Metrics.control: die Kapsel ist
        // exakt so hoch wie der Anlegen-Knopf breit ist, und der innere
        // Auswahl-Radius ist genau um den Rand kleiner als der äußere.
        .padding((Theme.Metrics.control - Theme.Metrics.hit) / 2)
        .modifier(ChromeGlass(id: "chrome-nav", namespace: glassNamespace, kind: .capsule,
                              union: chromeUnion("chrome-nav-solo")))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-switcher")
    }

    /// Ein Symbol im Chrom. Gleiches Kästchen für alle drei, damit die
    /// Mittelpunkte auf EINER Linie sitzen — die Punktgrößen sind dagegen
    /// OPTISCH abgeglichen und nicht gleich: bei identischer Punktgröße wiegt
    /// das 2x2-Raster deutlich schwerer als drei Punkte, und das Plus liest
    /// sich größer als beide. Die Zahlen sind am Bildschirm nachjustiert.
    private func glyph(_ symbol: String) -> some View {
        let size: CGFloat
        switch symbol {
        case "square.grid.2x2": size = 15   // kompaktes, fettes Zeichen
        case "ellipsis":        size = 17   // drei Punkte wirken winzig
        case "plus":            size = 17   // wirkt bei gleicher Größe zu groß
        default:                size = 17
        }
        return Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: Theme.Metrics.glyph, height: Theme.Metrics.glyph)
    }

    private func tabButton(_ target: Screen, symbol: String, title: String, id: String) -> some View {
        Button {
            screen = target
        } label: {
            HStack(spacing: 4) {
                glyph(symbol)
                if !collapsed {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .fixedSize()
                        .padding(.trailing, 8)
                }
            }
            // Die Auswahl-Fläche ist genau so hoch wie die Symbolkästchen —
            // zusammengezogen also ein Kreis von derselben Größe wie seine
            // Nachbarn, nicht der große grüne Klecks von vorher.
            .frame(height: Theme.Metrics.glyph)
            .padding(.leading, collapsed ? 0 : 8)
            .background {
                if screen == target {
                    // Kein beliebiger Alpha-Wert, sondern die eine
                    // Auswahl-Lasur der App: die Markenfarbe so weit
                    // heruntergezogen, dass sie hinter Glas noch als Fläche
                    // liest, ohne den Text zu schlucken.
                    Capsule().fill(Theme.accent(store.palette).opacity(0.18))
                }
            }
            // Trefferfläche bleibt 44 pt hoch, auch wenn das Sichtbare 32 ist.
            .frame(height: Theme.Metrics.hit)
            .contentShape(Rectangle())
            // `.primary` statt `.secondary`: über einem dicht gefüllten
            // Raster ist Sekundärgrau hinter Glas nicht mehr lesbar. Die
            // Hierarchie trägt die Auswahl-Lasur, nicht die Textfarbe.
            .foregroundStyle(screen == target
                             ? AnyShapeStyle(Theme.accentText(store.palette))
                             : AnyShapeStyle(HierarchicalShapeStyle.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(screen == target ? [.isSelected] : [])
        .accessibilityIdentifier(id)
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
                                 ? AnyShapeStyle(Theme.accentText(store.palette))
                                 : AnyShapeStyle(.white))
                .frame(width: Theme.Metrics.control, height: Theme.Metrics.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ChromeGlass(id: "chrome-add", namespace: glassNamespace,
                              kind: .circle,
                              accent: collapsed ? nil : store.palette,
                              union: chromeUnion("chrome-add-solo")))
        .accessibilityLabel(String(localized: "Habit hinzufügen"))
        .accessibilityIdentifier("add-habit")
    }

    // Bewusst KEIN `.tabViewBottomAccessory`: die Zubehörleiste ist Apples
    // Now-Playing-Slot (volle Breite, persistenter Status). Als Anlegen-
    // Aktion belegt sie dauerhaft einen Streifen über dem Raster —
    // ausprobiert, sieht nach echtem Glas aus, ist aber die falsche Rolle.

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
            screen = .habits
            morePath = NavigationPath()
        case "more", "sync":
            // "sync" landet im Mehr-Bereich; das Blatt öffnet MoreView
            // selbst (Debug-Argument bzw. Tippen auf die Zeile).
            screen = .more
            morePath = NavigationPath()
        case "stats":
            screen = .more
            morePath = NavigationPath([MoreRoute.stats])
        case "archive":
            screen = .more
            morePath = NavigationPath([MoreRoute.archive])
        case "search":
            screen = .habits
            morePath = NavigationPath()
            searching = true
            searchFieldFocused = true
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

    /// Nur Debug: rendert die Widget-Oberfläche in beiden Größen über die
    /// vier kritischen Datenlagen (keine Habits, leeres Log, Mengen-Habit,
    /// 365 Tage Historie) in den App-Group-Container. WidgetKit lässt sich
    /// nicht fernsteuern; so ist der Zustand trotzdem reproduzierbar prüfbar.
    @MainActor
    private func dumpWidgets() {
        var quantity = Habit(name: "Wasser", emoji: "💧", goal: Goal(target: 3))
        var long = Habit(name: "Lesen", emoji: "📚")
        for i in 0..<365 {
            guard let k = DayKey.shifted(DayKey.today(), by: -i) else { continue }
            if i % 4 != 0 { long.log[k] = 1 }
            quantity.log[k] = (i % 3) + 1
        }
        let scenarios: [(String, [Habit])] = [
            ("nohabits", []),
            ("emptylog", [Habit(name: "Neu", emoji: "🌱")]),
            ("quantity", [quantity]),
            ("year", [long]),
        ]
        let sizes: [(String, WidgetFamily, CGSize)] = [
            ("small", .systemSmall, CGSize(width: 170, height: 170)),
            ("medium", .systemMedium, CGSize(width: 364, height: 170)),
        ]
        let dir = SharedStorage.dataURL().deletingLastPathComponent()
        for (name, habits) in scenarios {
            for (sizeName, family, size) in sizes {
                let view = HaiityWidgetView(entry: HaiityEntry(date: .now,
                                                               habits: habits,
                                                               palette: store.palette))
                    .content(family: family)
                    .padding(12)
                    .frame(width: size.width, height: size.height)
                    .background(Color(.systemBackground))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                guard let png = renderer.uiImage?.pngData() else { continue }
                try? png.write(to: dir.appendingPathComponent("widget-\(sizeName)-\(name).png"))
            }
        }
    }

    /// Nur Debug: rendert die Teilen-Karte in BEIDEN Schemata in den
    /// App-Group-Container — so lässt sie sich prüfen, ohne durch das
    /// Teilen-Blatt zu klicken.
    @MainActor
    private func dumpShareCards() {
        guard let habit = store.activeHabits.first else { return }
        let dir = SharedStorage.dataURL().deletingLastPathComponent()
        for scheme in [ColorScheme.light, .dark] {
            guard let png = ShareCard.render(habit: habit, scheme: scheme, globalPalette: store.palette)?.pngData() else { continue }
            let name = scheme == .dark ? "sharecard-dark.png" : "sharecard-light.png"
            try? png.write(to: dir.appendingPathComponent(name))
        }
    }
    #endif

    // MARK: – Boot / Sync / Reminder (unverändert aus v1)

    private func boot() async {
        await sync.restore()
        connectedLogin = await sync.login
        HaiityShortcuts.updateAppShortcutParameters()
        store.onChange = { [weak store] in
            guard let store else { return }
            schedulePush(store)
            Task { await rescheduleReminders() }
            // Habit-Namen können sich geändert haben -> Siri-Phrasen auffrischen.
            HaiityShortcuts.updateAppShortcutParameters()
        }
        if connectedLogin != nil, let remote = try? await sync.pull() {
            store.merge(remote: remote)
        }
        await rescheduleReminders()
    }

    private func rescheduleReminders() async {
        await Reminders.reschedule(
            habits: store.habits,
            summaryMinutes: store.summaryMinutes,
            openToday: store.openToday())
    }

    private func schedulePush(_ store: HabitStore) {
        guard connectedLogin != nil else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let payload = store.exportJSON() else { return }
            do {
                try await sync.push(payload) { remote in
                    if let remote {
                        await MainActor.run { store.merge(remote: remote) }
                    }
                    return await MainActor.run { store.exportJSON() ?? payload }
                }
                await MainActor.run { syncStatus = String(localized: "✓ synchronisiert") }
            } catch {
                await MainActor.run { syncStatus = error.localizedDescription }
            }
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { syncStatus = "" }
        }
    }
}

// MARK: – Scroll-Signal

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
    var accent: GraphPalette?
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

/// Die Sync-Pille braucht kein Morphing, nur eine Fläche.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
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

/// Suchfeld, das NICHT dauerhaft sichtbar ist. Es gibt die Suchleiste erst,
/// wenn die Lupe im Toolbar-Blob getippt wurde — `.searchable` hängt bis
/// dahin GAR NICHT am Baum.
///
/// Der Umweg ist Absicht, beide naheliegenden Wege scheitern an Punkt 2 der
/// Rückmeldung („Lupe und Menü als EIN Blob"):
///  * `.searchToolbarBehavior(.minimize)` (ab iOS 26) versteckt die Leiste
///    zwar, setzt dafür aber eine ZWEITE, systemeigene Lupe als eigene Blase
///    neben den Blob — genau die doppelte Blase, die wegsollte.
///  * `.navigationBarDrawer(displayMode: .automatic)` blendet die Leiste am
///    Listenanfang dauerhaft ein; „standardmäßig unsichtbar" ist sie damit
///    auch nicht.
/// Bleibt: den Modifier an den Zustand hängen. Das System bekommt
/// `isPresented` bereits als `true` und klappt die Leiste beim Anhängen auf;
/// „Abbrechen" setzt es zurück, der Modifier fällt wieder weg.
private struct SearchableHidden: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let focus: FocusState<Bool>.Binding
    let prompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPresented {
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
                          prompt: String) -> some View {
        modifier(SearchableHidden(text: text, isPresented: isPresented,
                                  focus: focus, prompt: prompt))
    }
}

/// Deko fürs Empty-State: ein kleines zufälliges Contribution-Muster.
private struct DemoGrid: View {
    let palette: GraphPalette
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
