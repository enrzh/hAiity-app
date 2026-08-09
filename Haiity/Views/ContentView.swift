import SwiftUI
import AppIntents
import WidgetKit

/// Haupt-Einstieg: ECHTE TabView mit zwei Bereichen (Habits / Mehr), jeder
/// in eigenem NavigationStack. Ab iOS 26 rendert das System seine
/// schwebende Liquid-Glass-Tab-Bar (die minimiert beim Scrollen); darunter
/// bleibt die klassische Tab-Bar. Der runde + ist ab iOS 26 echtes Glas
/// (`glassEffect`), darunter der gefüllte Kreis wie bisher.
/// Boot-/Sync-/Reminder-Verkabelung ist 1:1 aus v1 übernommen.
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        tabs
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
    }

    // MARK: – Tab-Gerüst

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26, *) {
            TabView(selection: $screen) {
                // ACHTUNG (iOS 26.4 verifiziert): die native Tab-Bar
                // übernimmt den accessibilityIdentifier NICHT — weder vom
                // Tab noch von einem eigenen Label. In XCUITest sind die
                // Tabs nur über ihr Label erreichbar
                // (app.tabBars.buttons["Habits"]). Der Identifier bleibt
                // trotzdem gesetzt, falls Apple das nachzieht.
                Tab(String(localized: "Habits"), systemImage: "square.grid.2x2", value: Screen.habits) {
                    habitsStack
                }
                .accessibilityIdentifier("tab-habits")
                Tab(String(localized: "Mehr"), systemImage: "ellipsis", value: Screen.more) {
                    moreStack
                }
                .accessibilityIdentifier("tab-more")
            }
            // Beim Scrollen nach unten schrumpft die Glas-Bar auf ein
            // Pillchen — das Raster bekommt den Platz.
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            TabView(selection: $screen) {
                habitsStack
                    .tabItem {
                        Label(String(localized: "Habits"), systemImage: "square.grid.2x2")
                    }
                    .tag(Screen.habits)
                    .accessibilityIdentifier("tab-habits")
                moreStack
                    .tabItem {
                        Label(String(localized: "Mehr"), systemImage: "ellipsis")
                    }
                    .tag(Screen.more)
                    .accessibilityIdentifier("tab-more")
            }
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
                .overlay(alignment: .bottom) { syncBadge }
        }
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
                // Bei offener Suche steht der + sonst über der Tastatur.
                .overlay(alignment: .bottomTrailing) { if !searching { addButton } }
                .overlay(alignment: .bottom) { syncBadge }
        } else {
            habitList
                .navigationTitle("Habits")
                .searchableHidden(text: $search,
                                  isPresented: $searching,
                                  focus: $searchFieldFocused,
                                  prompt: String(localized: "Habits durchsuchen"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
                // Bei offener Suche steht der + sonst über der Tastatur.
                .overlay(alignment: .bottomTrailing) { if !searching { addButton } }
                .overlay(alignment: .bottom) { syncBadge }
        }
    }

    private var habitList: some View {
        List {
            if filteredHabits.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredHabits) { habit in
                    row(for: habit)
                }
                .onMove(perform: search.isEmpty
                    ? { store.move(fromOffsets: $0, toOffset: $1) }
                    : nil)
            }
        }
        .listStyle(.plain)
        // Karten sind weiß/#1C1C1E, die Seite muss also die gruppierte
        // Fläche sein. Kein toolbarBackground-Override — die Navigations-
        // leiste behält ihr System-Glas.
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private func row(for habit: Habit) -> some View {
        HabitCard(
            habit: habit,
            onToggleDay: { store.toggle(habit.id, day: $0) },
            onIncrement: { store.increment(habit.id) },
            onClear: { store.clear(habit.id) },
            onEdit: { editing = habit },
            onArchive: { store.archive(habit.id) }
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                store.archive(habit.id)
            } label: {
                Label(String(localized: "Archivieren"), systemImage: "archivebox")
            }
            .tint(.orange)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DemoGrid()
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
                    .background(Theme.accentFill, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-first-habit")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: – Schwebender + (echtes Glas ab iOS 26)

    @ViewBuilder
    private var addButton: some View {
        if #available(iOS 26, *) {
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Theme.accent).interactive(), in: .circle)
            .padding(.trailing, 18)
            .padding(.bottom, 10)
            .accessibilityLabel(String(localized: "Habit hinzufügen"))
            .accessibilityIdentifier("add-habit")
        } else {
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Theme.accentFill, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 10)
            .accessibilityLabel(String(localized: "Habit hinzufügen"))
            .accessibilityIdentifier("add-habit")
        }
    }

    // Bewusst KEIN `.tabViewBottomAccessory`: die Zubehörleiste ist Apples
    // Now-Playing-Slot (volle Breite, persistenter Status). Als Anlegen-
    // Aktion belegt sie dauerhaft einen Streifen über dem Raster —
    // ausprobiert, sieht nach echtem Glas aus, ist aber die falsche Rolle.

    /// Kurzlebige Sync-Rückmeldung — früher in der eigenen Bottom-Bar,
    /// jetzt eine kleine Glas-Pille über der Tab-Bar.
    @ViewBuilder
    private var syncBadge: some View {
        if !syncStatus.isEmpty {
            Group {
                if #available(iOS 26, *) {
                    Text(syncStatus)
                        .font(.caption2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                } else {
                    Text(syncStatus)
                        .font(.caption2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
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
                let view = HaiityWidgetView(entry: HaiityEntry(date: .now, habits: habits))
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
            guard let png = ShareCard.render(habit: habit, scheme: scheme)?.pngData() else { continue }
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

/// Suchfeld, das NICHT dauerhaft sichtbar ist: ab iOS 26 klappt es zu einem
/// Glas-Lupenknopf in der Toolbar zusammen und öffnet sich erst beim Tippen;
/// darunter liegt es als Navigation-Bar-Drawer unter dem Titel versteckt
/// (erscheint erst beim Herunterziehen der Liste).
private struct SearchableHidden: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let focus: FocusState<Bool>.Binding
    let prompt: String

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .searchable(text: $text, isPresented: $isPresented, prompt: Text(prompt))
                .searchFocused(focus)
                .searchToolbarBehavior(.minimize)
        } else {
            let base = content
                .searchable(text: $text,
                            isPresented: $isPresented,
                            placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: Text(prompt))
            // searchFocused gibt es erst ab iOS 18; darunter reicht der
            // isPresented-Binding.
            if #available(iOS 18, *) {
                base.searchFocused(focus)
            } else {
                base
            }
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
    @Environment(\.colorScheme) private var scheme
    private let pattern: [Int] = (0..<48).map { _ in
        Bool.random() && Bool.random() ? Int.random(in: 1...4) : 0
    }

    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(14), spacing: 3), count: 12)
        LazyVGrid(columns: cols, spacing: 3) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.level(level, dark: scheme == .dark))
                    .frame(height: 14)
            }
        }
        .frame(width: 12 * 17)
        .accessibilityHidden(true)
    }
}
