import SwiftUI
import UIKit
import AppIntents
import WidgetKit

/// Haupt-Einstieg. EIN Bereich (die Habit-Liste in ihrem NavigationStack)
/// plus „Mehr" als Tafel, die AUS der Leiste unten wächst — umgeschaltet von
/// einem EIGENEN Umschalter unten LINKS, nicht von einer TabView.
///
/// „Mehr" war einmal ein zweiter Bildschirm im Umschalter. Das war die
/// falsche Form: Einstellungen sind kein Ort, an dem man sich aufhält, und
/// der Wechsel riss die Liste weg, obwohl man nur kurz eine Farbe umstellen
/// wollte. Jetzt klappt die Tafel über der Leiste auf, die Leiste bleibt
/// stehen und die Liste liegt sichtbar dahinter. Bildschirmartige Ziele
/// (Statistik, Archiv, Über) sind BLÄTTER — sie haben eine eigene
/// Navigationsleiste und einen eigenen Titel und hätten in einer Tafel, die
/// an der Unterkante klebt, keinen Platz.
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
    /// iCloud-Spiegel. Der lokale Stand in `store` ist die Wahrheit; das hier
    /// trägt ihn nur zur Apple-ID hinüber (siehe CloudSync).
    @State private var cloud = CloudSync()
    @State private var cloudStatus = CloudSyncStatus()
    /// Fasst schnelle Folgeänderungen zu EINEM Upload zusammen.
    @State private var pushes = PushDebouncer()
    @State private var editing: Habit?
    @State private var showAdd = false
    @State private var syncStatus = ""
    /// `.more` heißt jetzt: die Tafel über der Leiste ist offen. Es ist kein
    /// zweiter Bildschirm mehr, aber weiterhin der Zustand der Auswahl-Lasur
    /// im Umschalter — genau eine Wahrheit für beides.
    @State private var screen: Screen = .habits
    /// Bildschirmartige Unterziele des Mehr-Bereichs, als Blatt.
    @State private var moreSheet: MoreRoute?
    /// Rahmen der beiden Umschalter-Segmente im Umschalter-Koordinatenraum.
    /// Grundlage des Treffertests beim Ziehen (siehe ChromeLayout.segment).
    @State private var segmentFrames: [Screen: CGRect] = [:]
    /// Segment unter dem gedrückten Finger. Solange gezogen wird, zeigt die
    /// Lasur HIERHIN und nicht auf `screen` — die Auswahl gilt erst beim
    /// Loslassen.
    @State private var dragSegment: Screen?
    @State private var draggingSwitcher = false
    /// Größe und Zug der Tafel stehen NICHT mehr hier, sondern in
    /// `MorePanelSurface`. Der Grund ist gemessen, nicht ästhetisch: solange
    /// der Zug an einem `@State` DIESER Ansicht hing, wertete SwiftUI bei
    /// jedem Bildschritt den ganzen `body` neu aus — samt Habit-Liste, samt
    /// jeder Karte darin. Beim schnellen Auf- und Zuziehen fielen dabei
    /// reproduzierbar Bilder aus. Der Zustand gehört der Tafel, also gehört
    /// er in die Tafel.
    ///
    /// Nebeneffekt, der ausdrücklich erwünscht ist: die Tafel öffnet immer
    /// klein, weil ihr Zustand mit ihr entsteht und mit ihr vergeht.
    /// Der eine Wert, der die Tafel doch verlässt: wie weit sie aufgezogen
    /// ist. Er hängt an einem beobachtbaren Objekt und NICHT an einem `@State`
    /// dieser Ansicht — gelesen wird er ausschließlich von der kleinen Hülle
    /// um die Leiste (`WithdrawingChrome`), damit ein Zug weiterhin nicht den
    /// ganzen `body` hier neu auswertet. Siehe `MorePanelProgress`.
    @State private var panelProgress = MorePanelProgress()
    /// Wann zuletzt ein ZUG entschieden hat. Der Knopf, auf dem der Finger
    /// aufgesetzt hat, feuert danach trotzdem noch — siehe `select`.
    @State private var lastDragSwitch = Date.distantPast
    /// Fährt der Anlegen-Knopf gerade? Solange ja, KEINE gemeinsame
    /// Glas-Vereinigung (siehe `chromeUnion`).
    @State private var chromeTravelling = false
    @State private var search = ""
    /// Suchfeld ausgeklappt? Startet IMMER `false` — das Feld ist Standard
    /// unsichtbar und erscheint erst auf Tippen (bzw. per haiity://search).
    @State private var searching = false
    @FocusState private var searchFieldFocused: Bool
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
    private var collapsed: Bool { chromeCollapsed && screen == .habits && !searching }

    /// Ist die Mehr-Tafel offen?
    private var moreOpen: Bool { screen == .more }

    /// Auf welches Segment zeigt die Lasur GERADE? Beim Ziehen folgt sie dem
    /// Finger, sonst der getroffenen Wahl.
    private var highlighted: Screen { dragSegment ?? screen }

    private static let listSpace = "habit-list"
    private static let switcherSpace = "screen-switcher"

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
        return screens
            // Der Vorhang liegt ÜBER der Liste und UNTER dem Chrom: die
            // Leiste bleibt bedienbar, während die Tafel offen ist.
            .overlay { moreScrim }
            // Die Nacharbeiten-Karte liegt DAZWISCHEN: über dem Vorhang von
            // „Mehr", unter dem Chrom. Damit bleibt der Rückgängig-Toast
            // (der IM Chrom hängt) neben ihr sichtbar und bedienbar — und
            // genau die Änderungen, die am ehesten ein Zurück brauchen,
            // verlieren ihr Zurück nicht.
            .overlay { backfillLayer }
            // Chrom liegt ÜBER den Bereichen, nicht in ihnen: so bleibt es
            // beim Umschalten stehen und die Listen scrollen darunter durch.
            .overlay(alignment: .bottom) { bottomChrome }
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
            .sheet(isPresented: $showAdd) {
                EditHabitSheet(store: store)
                    .themed(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
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
            .onChange(of: screen) { _, _ in
                editMode = .inactive
                expandChrome()
                // Ein Toast, der auf eine Karte zeigt, die man nicht mehr
                // sieht, ist nur noch ein Knopf ins Ungewisse.
                undo.clear()
                // Dasselbe für die Nacharbeiten-Karte: sie gehört zu einer
                // Zeile der Liste, und die ist gerade weggeklappt worden.
                backfill = nil
            }
            .onChange(of: searching) { _, _ in
                // Auf- und Zuklappen der Suche ist ein Layout-Sprung, kein
                // Scrollen — den Lauf verwerfen, sonst wirkt er hinterher nach.
                expandChrome()
            }
    }

    // MARK: – Bereiche

    /// Nur noch EIN Stapel. „Mehr" ist keine zweite Seite mehr, sondern die
    /// Tafel unten — die Liste bleibt sichtbar dahinter stehen.
    private var screens: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            habitsStack
                // Offene Tafel = modal: der Vorhang nimmt die Tipper, und
                // VoiceOver soll nicht durch ihn hindurchgreifen.
                .accessibilityHidden(moreOpen)
        }
    }

    private var habitsStack: some View {
        NavigationStack {
            habitsScreen
        }
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

    private func withCardAnimation(_ body: () -> Void) {
        if reduceMotion { body() } else { withAnimation(.snappy(duration: 0.22), body) }
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
                         onClose: { withCardAnimation { backfill = nil } })
                .transition(reduceMotion
                            ? AnyTransition.opacity
                            : AnyTransition.opacity.combined(with: .scale(scale: 0.92)))
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
        guard screen == .habits else { chrome.scroll.rebase(frames); return }
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
                    moreSheet = .stats
                } label: {
                    Label(String(localized: "Statistik"), systemImage: "chart.bar")
                }
                Button {
                    moreSheet = .archive
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
        .foregroundStyle(Theme.accentText(store.paletteStyle))
        .modifier(ToolbarBlob())
    }

    // MARK: – Chrom unten: Umschalter links, + in der rechten Ecke

    @ViewBuilder
    private var bottomChrome: some View {
        // Bei offener Suche steht das Chrom sonst auf der Tastatur. Der
        // Toast hängt bewusst MIT drin: er soll über dem Glas-Blob schweben,
        // nicht darauf — und auf der Tastatur hätte er nichts verloren.
        //
        // Die Mehr-Tafel hängt ebenfalls hier, im SELBEN Glas-Behälter wie
        // die Leiste: sie ist kein Blatt über der App, sondern dasselbe
        // Glasstück, das nach oben wächst.
        if !searching {
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
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 20) { chromeColumn }
        } else {
            chromeColumn
        }
    }

    /// Tafel und Leiste, in DIESER Reihenfolge — die Leiste wird nach der
    /// Tafel gezeichnet und liegt damit auf deren unterem Überstand. Genau
    /// das ist auf der KARTE richtig (die Tafel wächst aus der Leiste heraus)
    /// und auf der GANZEN SEITE falsch: dort steht sonst ein Umschalter
    /// mitten in einer bildschirmfüllenden Fläche. Deshalb die Hülle: sie
    /// zieht die Leiste am SELBEN Fortschritt zurück, an dem auch Höhe,
    /// Radius und Überstand hängen.
    private var chromeColumn: some View {
        VStack(spacing: Theme.Metrics.gap) {
            morePanel
            WithdrawingChrome(panel: panelProgress, content: chromeStack)
        }
    }

    /// Die Tafel als EIGENE Ansicht — und das ist keine Aufräumaktion,
    /// sondern die Behebung des Ruckelns beim schnellen Auf- und Zuziehen
    /// (nachgemessen, siehe `MorePanelSurface`): der Zug hält seinen Zustand
    /// dort, wo er hingehört, und lässt diesen `body` in Ruhe.
    @ViewBuilder
    private var morePanel: some View {
        if moreOpen {
            MorePanelSurface(store: store,
                             cloudStatus: cloudStatus,
                             namespace: glassNamespace,
                             chrome: panelProgress,
                             onOpen: { moreSheet = $0 },
                             onDismiss: { select(.habits) })
        }
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

    @ViewBuilder
    private var moreScrim: some View {
        if moreOpen {
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { select(.habits) }
                .transition(.opacity)
                .accessibilityLabel(String(localized: "Mehr schließen"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("more-scrim")
        }
    }

    /// Linksbündige Glas-Kapsel mit beiden Bereichen. Zusammengezogen fallen
    /// die Beschriftungen weg — beide Ziele bleiben aber Knöpfe (und ihre
    /// Identifier im Baum), der Blob ist kein totes Abzeichen.
    ///
    /// **Konzentrik.** Die Auswahl-Lasur liegt IN der Kapsel, also muss ihr
    /// Radius exakt der äußere MINUS dem Rand sein — sonst läuft der Spalt
    /// zwischen beiden Bögen um die Rundung herum auseinander, und genau das
    /// sieht man. Die Rechnung, in beiden Zuständen dieselbe:
    ///
    ///     äußere Kapsel  H = control = 52  ->  R = H/2 = 26
    ///     Rand           p = (control − hit)/2 = 4   (rundum gleich)
    ///     innere Kapsel  h = control − 2p = hit = 44  ->  r = h/2 = 22
    ///     Probe:         r = R − p  ->  22 = 26 − 4  ✓
    ///
    /// Beide Formen sind ECHTE Kapseln (Stadion), der Radius ist also die
    /// halbe Höhe und nicht geraten. Damit das auch waagerecht stimmt, ist
    /// die Lasur mindestens `hit` breit (`chromeInset` unten) — eine Kapsel,
    /// die schmaler als hoch ist, bekäme den Radius aus der KLEINEREN Seite
    /// und liefe zusammengezogen aus der Konzentrik.
    private var switcher: some View {
        HStack(spacing: Self.chromeInset) {
            tabButton(.habits, symbol: "square.grid.2x2",
                      title: String(localized: "Habits"), id: "tab-habits")
            tabButton(.more, symbol: "ellipsis",
                      title: String(localized: "Mehr"), id: "tab-more")
        }
        // RUNDUM derselbe Rand — links wie rechts wie oben wie unten.
        .padding(Self.chromeInset)
        // Die Lasur liegt als EIN Stück HINTER beiden Zielen und wird über
        // gemessene Segmentrahmen positioniert. Vorher zeichnete jedes Ziel
        // seine eigene: dann kann sie nicht wandern, sie kann nur blinken.
        .background(alignment: .topLeading) { selectionLasur }
        .coordinateSpace(.named(Self.switcherSpace))
        .modifier(ChromeGlass(id: "chrome-nav", namespace: glassNamespace, kind: .capsule,
                              union: chromeUnion("chrome-nav-solo")))
        .onPreferenceChange(SegmentFrameKey.self) { segmentFrames = $0 }
        // `simultaneousGesture`, nicht `gesture`: die beiden Knöpfe darin
        // bleiben Knöpfe (Tippen, VoiceOver, XCUITest), und der Zug läuft
        // parallel dazu.
        .simultaneousGesture(segmentDrag)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-switcher")
    }

    /// Die Auswahl-Lasur — EIN Stück Farbe, das über die Segmente FÄHRT.
    ///
    /// Ihre Lage kommt aus den gemessenen Segmentrahmen, nicht aus dem
    /// Layout: nur so lässt sie sich zwischen zwei Segmenten interpolieren,
    /// und nur so kann sie einem gedrückten Finger folgen, ohne dass sich
    /// darunter irgendetwas bewegt. Beim Ziehen wird sie eine Spur kräftiger
    /// — die Rückmeldung des Glases (`interactive()`) besorgt den Rest.
    @ViewBuilder
    private var selectionLasur: some View {
        if let frame = segmentFrames[highlighted], frame.width > 0 {
            Capsule()
                // Kein beliebiger Alpha-Wert, sondern die eine Auswahl-Lasur
                // der App: die Markenfarbe so weit heruntergezogen, dass sie
                // hinter Glas noch als Fläche liest, ohne den Text zu
                // schlucken.
                .fill(Theme.accent(store.paletteStyle)
                        .opacity(draggingSwitcher ? 0.26 : 0.18))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                // Bewegung reduzieren: kein Mitlaufen, nur der Endzustand.
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.24,
                                                                   dampingFraction: 0.86),
                           value: frame)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: draggingSwitcher)
        }
    }

    /// Drücken und ziehen wie bei der System-Tableiste: die Lasur folgt dem
    /// Finger über die Segmente und bleibt beim Loslassen stehen.
    ///
    /// Kein Schieberegler: die Lasur setzt sich immer auf ein GANZES Segment
    /// (Treffertest auf den gemessenen Rahmen, siehe ChromeLayout.segment),
    /// sie steht nie dazwischen. Losgelassen wird die Wahl übernommen;
    /// ausserhalb losgelassen heißt Abbruch, und sie schnappt zurück.
    private var segmentDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.switcherSpace))
            .onChanged { value in
                // Bei „Bewegung reduzieren" gibt es kein Mitlaufen — dort
                // zählt nur der Endzustand.
                guard !reduceMotion else { return }
                if !draggingSwitcher { draggingSwitcher = true }
                guard let hit = ChromeLayout.segment(at: value.location, frames: segmentFrames),
                      hit != dragSegment else { return }
                dragSegment = hit
                // Dieselbe kurze Rückmeldung wie beim Abhaken, sobald die
                // Lasur ein anderes Ziel erreicht.
                if hit != screen { Theme.Haptics.check() }
            }
            .onEnded { value in
                draggingSwitcher = false
                dragSegment = nil
                // Ein reiner TIPP gehört dem Knopf — sonst entscheiden beide
                // über dasselbe Ereignis. Erst ein echter Zug wird hier
                // übernommen.
                let moved = abs(value.translation.width) > 4 || abs(value.translation.height) > 4
                guard moved,
                      let hit = ChromeLayout.segment(at: value.location, frames: segmentFrames)
                else { return }
                select(hit, from: .drag)
            }
    }

    /// Der eine Rand, aus dem beide Radien folgen: (52 − 44)/2 = 4. Er ist
    /// auch der Abstand ZWISCHEN den beiden Lasuren, damit der Spalt überall
    /// im Blob derselbe ist.
    private static let chromeInset: CGFloat = ChromeLayout.inset

    /// Woher die Wahl kommt. Nicht kosmetisch: die beiden Wege schließen
    /// einander aus, und ohne diese Unterscheidung heben sie sich auf.
    private enum SwitchSource { case tap, drag }

    /// Bereich wählen. „Mehr" ist ein UMSCHALTER: noch einmal darauf klappt
    /// die Tafel wieder zu.
    ///
    /// **Der Zug gewinnt.** Knopf und Ziehgeste laufen simultan. Zieht man
    /// von „Habits" nach „Mehr" und lässt dort los, entscheidet die Geste
    /// richtig — und danach feuert der Knopf, auf dem der Finger AUFGESETZT
    /// hat, trotzdem noch seine eigene Aktion und nimmt die Wahl sofort
    /// wieder zurück. Nachgemessen: die Tafel ging auf und im selben Bild
    /// wieder zu. Deshalb sperrt eine frische Zug-Entscheidung den Knopf
    /// für einen Wimpernschlag.
    private func select(_ target: Screen, from source: SwitchSource = .tap) {
        let now = Date()
        switch source {
        case .drag:
            lastDragSwitch = now
        case .tap:
            guard now.timeIntervalSince(lastDragSwitch) > 0.35 else { return }
        }
        let next: Screen = (target == .more && moreOpen) ? .habits : target
        guard next != screen else { return }
        // Die Tafel öffnet IMMER klein. Der große Zustand ist eine Geste, die
        // man gerade gemacht hat, keine Einstellung, die man später
        // wiederfinden muss — und eine Tafel, die beim nächsten Tippen
        // bildschirmfüllend aufspringt, überrascht. Der Zustand selbst lebt IN
        // der Tafel und geht mit ihr; hier steht nur die AUSSENSICHT darauf
        // gerade, damit die Leiste beim Schließen wieder mitkommt.
        //
        // Sie muss IN dieser Transaktion zurückgesetzt werden: käme sie erst
        // hinterher (etwa aus `onDisappear` der Tafel), stünde die Leiste die
        // ganze Schließbewegung lang noch weg und poppte danach herein.
        if reduceMotion {
            screen = next
            panelProgress.value = 0
        } else {
            withAnimation(PanelMotion.open) {
                screen = next
                panelProgress.value = 0
            }
        }
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
            select(target)
        } label: {
            HStack(spacing: 4) {
                glyph(symbol)
                if !collapsed {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .fixedSize()
                }
            }
            // Gleicher Innenabstand links wie rechts — vorher hing das
            // Padding einseitig am Symbol bzw. am Text, dadurch stand die
            // Beschriftung in der Lasur nicht mittig.
            .padding(.horizontal, collapsed ? 0 : Theme.Metrics.gap)
            // Die Lasur IST die Trefferfläche: `hit` hoch UND mindestens
            // `hit` breit. Damit ist sie eine Kapsel mit Radius hit/2 = 22,
            // also exakt (26 − 4) — konzentrisch zur Glaskapsel, in beiden
            // Zuständen (siehe `switcher`).
            .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
            // Statt einer eigenen Lasur nur noch der Messfühler: er meldet,
            // WO dieses Segment liegt. Gezeichnet wird die eine gemeinsame
            // Lasur eine Ebene höher (`selectionLasur`).
            .background { segmentProbe(target) }
            .contentShape(Capsule())
            // `.primary` statt `.secondary`: über einem dicht gefüllten
            // Raster ist Sekundärgrau hinter Glas nicht mehr lesbar. Die
            // Hierarchie trägt die Auswahl-Lasur, nicht die Textfarbe.
            .foregroundStyle(highlighted == target
                             ? AnyShapeStyle(Theme.accentText(store.paletteStyle))
                             : AnyShapeStyle(HierarchicalShapeStyle.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(screen == target ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    /// Meldet den Rahmen EINES Segments im Umschalter-Koordinatenraum.
    private func segmentProbe(_ target: Screen) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SegmentFrameKey.self,
                value: [target: geo.frame(in: .named(Self.switcherSpace))])
        }
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
        .buttonStyle(.plain)
        .modifier(ChromeGlass(id: "chrome-add", namespace: glassNamespace,
                              kind: .circle,
                              accent: collapsed ? nil : store.paletteStyle,
                              union: chromeUnion("chrome-add-solo")))
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
        // Jeder Weg über den Umschalter oder einen Link fängt bei der KARTE
        // an — es gibt keinen Link, der die Tafel gleich als ganze Seite
        // öffnet. Der Fortschritt steht deshalb überall dort, wo `screen`
        // gesetzt wird, ausdrücklich wieder auf 0: die Leiste ist dann da,
        // egal aus welchem Zustand man kam.
        switch url.host ?? url.lastPathComponent {
        case "habits":
            screen = .habits
            panelProgress.value = 0
            moreSheet = nil
        case "more", "sync":
            // Steht sie schon offen, ist der Link erfüllt — und zwar auch
            // dann, wenn sie gerade als ganze Seite dasteht. Hier NICHTS zu
            // tun ist die richtige Antwort: ein Zurücksetzen des
            // Fortschritts holte sonst die Leiste zurück, während die Tafel
            // weiterhin den ganzen Bildschirm füllt (ihre Größe lebt IN ihr
            // und kann von hier aus gar nicht mitgezogen werden).
            guard screen != .more else { break }
            // "sync" landet ebenfalls in der Tafel — die iCloud-Zeile steht
            // dort ganz oben. MIT Animation, wie ein Tipp auf den Umschalter:
            // die Tafel wächst aus der Leiste. Ein Sprung wäre an dieser
            // einen Stelle eine andere App.
            panelProgress.value = 0
            if reduceMotion { screen = .more }
            else { withAnimation(PanelMotion.open) { screen = .more } }
        case "stats":
            moreSheet = .stats
        case "archive":
            moreSheet = .archive
        case "search":
            screen = .habits
            panelProgress.value = 0
            moreSheet = nil
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
            if announce { await flash(String(localized: "✓ in iCloud gesichert")) }
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
}

/// Oberkanten aller sichtbaren Zeilen, Index -> minY im Listen-Koordinatenraum.
private struct RowOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { a, _ in a }
    }
}

/// Rahmen der Umschalter-Segmente im Umschalter-Koordinatenraum. Grundlage
/// für die wandernde Lasur UND für den Treffertest beim Ziehen — beide
/// müssen dieselben Zahlen sehen, sonst springt die Auswahl woanders hin,
/// als die Lasur steht.
private struct SegmentFrameKey: PreferenceKey {
    static var defaultValue: [ContentView.Screen: CGRect] = [:]
    static func reduce(value: inout [ContentView.Screen: CGRect],
                       nextValue: () -> [ContentView.Screen: CGRect]) {
        value.merge(nextValue()) { _, next in next }
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
