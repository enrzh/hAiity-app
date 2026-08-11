import SwiftUI
import UIKit

/// „Nacharbeiten": die Karte, in der VERGANGENE Tage nachgetragen werden.
///
/// Sie steht in der MITTE, nicht als Blatt von unten. Zwei Gründe: sie ist
/// kurz (Titel, Kalender, eine Zeile Status, ein, zwei Knöpfe) und sie ist
/// ein Zwischenschritt, kein Ort — ein Blatt, das über die halbe App fährt,
/// behauptet mehr Gewicht, als der Vorgang hat. Und: unten steht die Leiste
/// mit dem Rückgängig-Toast, und genau der muss neben ihr erreichbar bleiben.
///
/// **EINE Arbeitsweise: Auswählen.** Erst Tage sammeln, dann EINE Aktion auf
/// alle anwenden. Die Leiste kennt jeden Zielzustand der Habit-Art (auch
/// „Nein" und die Menge); die Auswahl bleibt nach der Aktion stehen, damit
/// die nächste gleich folgen kann. (Es gab einen zweiten Weg, „Malen" — er
/// ist auf Nutzerwunsch entfernt; die Mehr-Tafel hat keine Einstellung mehr
/// dazu.)
///
/// Die Karte SCHREIBT NICHT SELBST. Sie meldet „schreib diesen Wert an diese
/// Tage" (`onWrite`) nach oben — dort läuft alles durch dieselbe Stelle wie
/// jedes andere Abhaken, inklusive EINES Rückgängig pro Griff (`ContentView`).
struct BackfillCard: View {
    /// Der LEBENDE Habit aus dem Store: nach einem Schreibvorgang zeigt die
    /// Statuszeile sofort den neuen Stand, ohne die Karte zu schließen.
    let habit: Habit
    /// Der Tag, an dem die Karte geöffnet wurde (Rasterzelle bzw. Menü).
    /// Liegt beim Aufrufer; im Auswählen-Modus startet die Auswahl mit ihm.
    @Binding var day: String
    /// (Tage, Wert) — `nil` als Wert entfernt die Einträge. IMMER eine
    /// Liste, auch für einen Tag: der Aufrufer schreibt einen Vorgang, nicht
    /// n Vorgänge, und macht daraus EIN Zurück.
    let onWrite: ([String], Int?) -> Void
    /// (Tag, Vorwert) je Tag — der exakte Rückbau. Nur noch als
    /// VERTRÄGLICHKEITS-Anschluss: `ContentView` reicht den Rückbau-Weg
    /// weiterhin herein (die Datei wird parallel bearbeitet und bleibt hier
    /// unangetastet); die Karte selbst ruft ihn seit dem Ende des
    /// Malen-Modus nie mehr auf.
    let onRestore: ([(day: String, value: Int?)]) -> Void
    let onClose: () -> Void
    /// Wo die Karte HERKOMMT: die Lage der Habit-Zeile, deren langer Druck
    /// bzw. Zellentipp sie geöffnet hat, als Anker der Skalierung (0…1 der
    /// Bildschirmhöhe). Die Karte wächst aus ihrer Zeile heraus und schrumpft
    /// beim Schließen dorthin zurück, statt körperlos aus der Bildmitte zu
    /// blenden. Standard `.center`, damit Vorschauen und Tests sie ohne
    /// Herkunft bauen können.
    var sourceAnchor: UnitPoint = .center

    /// Die gewählten Tage. Der Kalender spricht `DateComponents`;
    /// umgerechnet wird an genau einer Stelle (`selectedKeys`).
    @State private var dates: Set<DateComponents> = []
    /// Stand des Mengen-Stellers. 0 = noch nicht angefasst -> Tagesziel.
    @State private var amount = 0
    /// Sperrklinke für die Höhe des Kalenders. `MultiDatePicker` misst sich
    /// nach dem ersten Layout noch einmal und wird dabei ein paar Punkte
    /// NIEDRIGER (nachgemessen: 554 -> 551,3 pt) — die Karte zuckte mit. Die
    /// größte je gesehene Höhe bleibt als Mindesthöhe stehen; das Blatt sitzt
    /// oben bündig, und die Karte steht still.
    @State private var multiHeight: CGFloat = 0

    @Environment(\.palettes) private var palettes
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Referenzmaß 100, skaliert mit Dynamic Type: `typeScale / 100` IST der
    /// Faktor, mit dem `.body` gerade wächst — dieselbe Messtechnik wie im
    /// Jahresraster (`ContributionGrid.labelScale`).
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 100

    /// Mengenwert für die Auswahl-Aktion: der Steller, sonst das Tagesziel.
    private var effectiveAmount: Int {
        amount > 0 ? amount : max(1, habit.recurrence.target ?? 1)
    }

    /// Die gewählten Tage als Tagesschlüssel, aufsteigend. Was der Kalender
    /// nicht in ein echtes Datum auflösen kann, fällt hier schon weg — der
    /// Schreibweg prüft trotzdem noch einmal (siehe `Backfill.canWrite`).
    private var selectedKeys: [String] {
        dates.compactMap { calendar.date(from: $0) }
            .map { DayKey.key(for: $0, calendar: calendar) }
            .sorted()
    }

    var body: some View {
        // Vorhang und Karte tragen GETRENNTE Übergänge, laufen aber in
        // DERSELBEN Transaktion (dem einen `withCardAnimation` des
        // Aufrufers): der Vorhang blendet nur, die Karte wächst aus ihrer
        // Zeile — beides mit derselben Kurve, als EINE Bewegung. Vorher
        // steckte die ganze Karte samt Vorhang in EINEM
        // Skalieren+Blenden-Übergang: der Vorhang wurde beim Öffnen sichtbar
        // MITSKALIERT (ein randloses Rechteck, das kurz Ränder hat) — genau
        // das „schlechte Fade" aus der Rückmeldung.
        ZStack {
            scrim
                .transition(.opacity)
            card
                .transition(reduceMotion
                            ? AnyTransition.opacity
                            : .scale(scale: 0.82, anchor: sourceAnchor)
                                .combined(with: .opacity))
        }
    }

    /// Der Vorhang gehört zur Karte: sie ist modal, und ein Tipp daneben ist
    /// der schnellste Weg hinaus.
    private var scrim: some View {
        Rectangle()
            .fill(Color.black.opacity(0.28))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .accessibilityLabel(String(localized: "Nacharbeiten schließen"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("backfill-scrim")
    }

    private var card: some View {
        // In den Accessibility-Größen wächst alles noch einmal.
        // `ViewThatFits` nimmt zuerst die ruhige Form (nichts scrollt) und
        // erst dann, wenn es wirklich nicht passt, die scrollende — statt auf
        // einem kleinen Gerät den Knopf unter den Bildschirmrand zu schieben.
        ViewThatFits(in: .vertical) {
            cardBody
            ScrollView { cardBody }
        }
        .frame(maxWidth: Self.maxWidth)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.top, Theme.Metrics.gutter)
        // Die Karte hält sich von der Leiste UND vom Rückgängig-Toast frei:
        // sie liegt UNTER dem Chrom, und der Toast (eine ~44-pt-Pille plus
        // Abstand über dem Blob) muss bei OFFENER Karte vollständig sichtbar
        // und antippbar bleiben — er ist das Zurück zu genau dem, was die
        // Karte gerade geschrieben hat.
        .padding(.bottom, Theme.Metrics.control + 2 * Theme.Metrics.gap
                 + Theme.Metrics.hit + Theme.Metrics.gap)
        // Die Karte ist modal: VoiceOver soll nicht durch sie hindurch in die
        // Liste greifen, die dahinter noch steht.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(String(localized: "Nacharbeiten: \(habit.name)"))
        .accessibilityIdentifier("backfill-card")
        .onAppear(perform: seed)
    }

    /// EINE Bedienzeile fester Höhe unter dem Kalender (die Aktion kommt
    /// nach dem Sammeln) — für jede Habit-Art dieselbe Höhe, die Karte
    /// springt beim Artwechsel nicht. Die Abstände sind bewusst KNAPP
    /// (10 statt 14 pt, oben/unten 12 statt 16): unten muss neben der Karte
    /// der Rückgängig-Toast stehen können, und jeder gesparte Punkt hier ist
    /// einer, den der Kalender behalten darf.
    private var cardBody: some View {
        VStack(spacing: 10) {
            header
            picker
            status
            actionRow
            closeButton
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, Theme.Metrics.cardPadding)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !habit.emoji.isEmpty { Text(habit.emoji).font(.title3) }
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(String(localized: "Tage auswählen, dann eintragen"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Maße der Karte
    //
    // Die Karte hat eine BERECHENBARE Breite: gedeckelt auf `maxWidth`, sonst
    // das Fenster minus der beiden Seitenränder. Daraus fällt das Innenmaß —
    // und aus dem Innenmaß die Höhe, die das Kalenderblatt reserviert.

    static let maxWidth: CGFloat = 360

    /// Feste Höhe der Aktionszeile — für JEDE Habit-Art dieselbe, sonst wäre
    /// die Karte bei „Menge" höher als bei „Ja/Nein".
    private static let controlRowHeight = Theme.Metrics.hit

    /// Innenmaß der Karte: die Breite, die Kopf, Kalender und Statuszeile
    /// wirklich bekommen.
    static func contentWidth(window: CGFloat) -> CGFloat {
        max(0, min(maxWidth, window - 2 * Theme.Metrics.gutter) - 2 * Theme.Metrics.gutter)
    }

    /// Breite des AKTIVEN Fensters, nicht die des Bildschirms — im Split View
    /// auf dem iPad sind das zwei verschiedene Zahlen (dieselbe Begründung wie
    /// bei der Vorschau in `HabitCard`).
    private static func windowWidth() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let width = scene?.keyWindow?.bounds.width, width > 0 { return width }
        if let width = scene?.screen.bounds.width, width > 0 { return width }
        return UIScreen.main.bounds.width
    }

    /// Die Höhe, die das Kalenderblatt VORAB bekommt — der Kern der
    /// Ruhig-Stehen-Zusage, siehe `Backfill.calendarHeight`.
    private var calendarHeight: CGFloat {
        Backfill.calendarHeight(width: Self.contentWidth(window: Self.windowWidth()),
                                typeScale: typeScale / 100)
    }

    /// Der Kalender: die Auswahl ist die Sammlung. Die Spanne kommt aus
    /// `Backfill` — die Zukunft ist damit gar nicht erst antippbar, und der
    /// älteste wählbare Tag ist derselbe, den auch das Raster noch zeigt.
    ///
    /// **Die Höhe wird RESERVIERT, nicht abgewartet** (`calendarHeight`), und
    /// die Sperrklinke `multiHeight` hält die größte je gemessene Höhe fest —
    /// zusammen steht die Karte vom ersten Bild an auf ihrem Endmaß.
    private var picker: some View {
        BackfillCalendar(dates: $dates,
                         habit: habit,
                         style: palettes.style(for: habit),
                         range: Backfill.dateRange(habit: habit, calendar: calendar),
                         calendar: calendar)
            // Oben bündig in der eigenen Reserve, und die wächst nur: misst
            // der Picker sich nach dem ersten Layout kleiner, hält die
            // Sperrklinke die Karte auf ihrem Maß.
            .frame(minHeight: max(multiHeight, calendarHeight), alignment: .top)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { multiHeight = max(multiHeight, g.size.height) }
                    .onChange(of: g.size.height) { _, h in
                        multiHeight = max(multiHeight, h)
                    }
            })
            .accessibilityIdentifier("backfill-date-picker")
    }

    /// Die lebende Statuszeile: wie viele Tage gewählt sind und wie viele
    /// davon schon zählen — der einzige Ort, an dem man VOR dem Schreiben
    /// sieht, was eine Aktion tatsächlich ändern wird.
    private var status: some View {
        let selection = Backfill.selection(habit: habit, days: Set(selectedKeys))
        let highlighted = selection.done > 0
        return Text(Backfill.selectionLine(habit: habit, days: Set(selectedKeys),
                                           calendar: calendar))
            .font(.subheadline)
            .foregroundStyle(highlighted
                             ? AnyShapeStyle(Theme.accentText(palettes.style(for: habit)))
                             : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            // IMMER eine Zeile. Der Text wechselt mit jedem Tipp; dürfte er
            // umbrechen, änderte sich mitten im Vorgang die Höhe der KARTE —
            // genau die Art Sprung, die diese Karte überall unterbindet.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("backfill-status")
    }

    private func stepButton(_ symbol: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: Self.controlRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    // MARK: – Auswählen

    private var selectActions: [Backfill.Action] {
        Backfill.selectActions(habit: habit, amount: effectiveAmount)
    }

    /// Die Aktionsleiste: jede Aktion gilt für ALLE gewählten Tage. Bei
    /// „Menge" steht der Steller mit in der Zeile — dieselbe Kapsel wie der
    /// Mengen-Pinsel, nur dass hier erst „Eintragen" schreibt.
    private var actionRow: some View {
        HStack(spacing: Theme.Metrics.gap) {
            if habit.kind == .quantity { selectAmountControl }
            ForEach(selectActions) { action in
                Button {
                    apply(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.controlRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(action.kind == .clear
                                 ? AnyShapeStyle(HierarchicalShapeStyle.primary)
                                 : AnyShapeStyle(Color.white))
                .background(fill(for: action), in: Capsule())
                .disabled(selectedKeys.isEmpty)
                .opacity(selectedKeys.isEmpty ? 0.4 : 1)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
        .frame(height: Self.controlRowHeight)
    }

    /// Der Mengen-Steller der Auswahl-Leiste: nur Minus / Stand / Plus — das
    /// Schreiben übernimmt daneben „Eintragen".
    private var selectAmountControl: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: effectiveAmount > 1) {
                Theme.Haptics.select()
                amount = max(1, effectiveAmount - 1)
            }
            .accessibilityLabel(String(localized: "Menge verringern"))
            .accessibilityIdentifier("backfill-amount-minus")
            Text("\(effectiveAmount)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 24)
                .accessibilityLabel(String(localized: "Menge: \(effectiveAmount)"))
                .accessibilityIdentifier("backfill-amount-value")
            stepButton("plus", enabled: effectiveAmount < Habit.Answer.maxCount) {
                Theme.Haptics.select()
                amount = min(Habit.Answer.maxCount, effectiveAmount + 1)
            }
            .accessibilityLabel(String(localized: "Menge erhöhen"))
            .accessibilityIdentifier("backfill-amount-plus")
        }
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    /// EINE Aktion auf ALLE gewählten Tage — die Auswahl bleibt danach
    /// stehen: wer eben sieben Tage auf „Ja" gestellt hat, kann sie sofort
    /// wieder anfassen (oder abwählen und die nächsten sammeln).
    private func apply(_ action: Backfill.Action) {
        let keys = selectedKeys
        guard !keys.isEmpty else { return }
        onWrite(keys, action.value)
        announce(String(localized: "\(keys.count) Tage: \(action.title)"))
    }

    /// Der Knopf trägt die Farbe seiner Bedeutung: „Nein" in der
    /// Verneinungsfarbe dieses Habits — derselben, in der der Tag gleich im
    /// Raster steht. Ein rot gemeinter Knopf in Akzentgrün wäre die einzige
    /// Stelle, an der die App die Zusage bricht, dass eine Farbe eine
    /// Bedeutung hat.
    private func fill(for action: Backfill.Action) -> AnyShapeStyle {
        let style = palettes.style(for: habit)
        switch action.kind {
        case .clear:    return AnyShapeStyle(Color(.tertiarySystemFill))
        case .declined: return AnyShapeStyle(Theme.color(style.negative(dark: scheme == .dark)))
        default:        return AnyShapeStyle(Theme.accentFill(style))
        }
    }

    /// „Fertig" als EIGENER Knopf mit Glas: die alte Fassung war eine
    /// flache Textzeile, die im Kartenboden verschwand. Jetzt eine helle
    /// Glas-Kapsel — ab iOS 26 echtes Liquid Glass (interaktiv), darunter
    /// dieselbe Material-Attrappe wie das Chrom. Der helle Tint (System-
    /// hintergrund, halbe Deckung) hebt sie in BEIDEN Schemata von der
    /// Karte ab, ohne aus Glas Milchglas zu machen.
    private var closeButton: some View {
        Button(action: onClose) {
            Text(String(localized: "Fertig"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(FertigGlass())
        .accessibilityIdentifier("backfill-close")
    }

    // MARK: – Tippen im Kalender

    /// Die Auswahl startet mit dem Tag, an dem die Karte geöffnet wurde —
    /// wer über eine Rasterzelle kam, findet genau sie vorausgewählt.
    private func seed() {
        guard dates.isEmpty,
              let date = DayKey.date(from: day, calendar: calendar) else { return }
        dates = [calendar.dateComponents([.era, .year, .month, .day], from: date)]
    }

    /// Gewählte Tage haben im Kalender ihren Auswahlkreis, eingetragene ihren
    /// Farbpunkt (siehe `BackfillCalendar`); WAS eine Aktion geschrieben hat,
    /// sagt VoiceOver zusätzlich hinterher — die Statuszeile zählt für alle
    /// Sehenden mit.
    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// Das Glas des Fertig-Knopfes. Ab iOS 26 `glassEffect` (interaktiv, mit
/// hellem Tint für Lesbarkeit auf der Karte in beiden Schemata), darunter
/// `.ultraThinMaterial` mit Haarlinie — dieselbe Rezeptur wie die
/// Glas-Pillen des Chroms, nur lokal, weil deren Modifier dort privat ist.
private struct FertigGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(
                .regular.tint(Color(.systemBackground).opacity(0.5)).interactive(),
                in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
        }
    }
}

// MARK: – Der Mehrfach-Kalender

/// `UICalendarView` mit `UICalendarSelectionMultiDate`, direkt eingebunden.
///
/// **Warum nicht SwiftUIs `MultiDatePicker`.** Der stand hier zuerst — und
/// sein Rückkanal ist auf diesem System kaputt: das ABWÄHLEN eines Tages
/// nimmt den Kreis aus dem Kalender, lässt den Tag aber im gebundenen Set
/// stehen (nachgemessen mit einem Log im `onChange`: das Auswählen feuert,
/// das Abwählen nie). Für das Malen hieße das „Antippen stellt zurück" geht
/// nie; für das Auswählen schlimmer: eine Aktion hätte STILL auch die Tage
/// getroffen, die man sichtbar abgewählt hatte. Der `UIKit`-Delegat meldet
/// beide Richtungen; die eine Wahrheit ist `selectedDates` der Selection.
private struct BackfillCalendar: UIViewRepresentable {
    @Binding var dates: Set<DateComponents>
    /// Der LEBENDE Habit — die Dekorationen unter den Tagen zeigen SEINE
    /// Daten und müssen nach jedem Schreibvorgang (und jedem Rückgängig aus
    /// dem Toast) den frischen Stand zeigen.
    let habit: Habit
    /// Die AUFGELÖSTE Palette des Habits: dieselben Farben, in denen seine
    /// Zellen im Jahresraster stehen.
    let style: PaletteStyle
    let range: ClosedRange<Date>
    let calendar: Calendar

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.availableDateRange = DateInterval(start: range.lowerBound,
                                               end: range.upperBound)
        view.delegate = context.coordinator
        let selection = UICalendarSelectionMultiDate(delegate: context.coordinator)
        selection.setSelectedDates(Array(dates), animated: false)
        view.selectionBehavior = selection
        // Die Karte reserviert die Höhe selbst (siehe `calendarHeight`);
        // das Blatt soll sich der Breite fügen, nicht die Karte sprengen.
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "backfill-date-picker"
        context.coordinator.decoratedLog = habit.log
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let previousLog = context.coordinator.decoratedLog
        context.coordinator.parent = self
        // Dekorationen NACHZIEHEN, wenn sich der Log geändert hat — der
        // Kalender fragt von selbst nie nach. Genau die Tage, deren Wert
        // sich unterscheidet (Schreibvorgang der Karte ODER Rückgängig aus
        // dem Toast bei offener Karte — beide ändern `habit.log` und laufen
        // hier durch). Der Vergleichsstand liegt im Coordinator, nicht in
        // einem @State: das hier ist Buchführung, keine Ansicht.
        if previousLog != habit.log {
            context.coordinator.decoratedLog = habit.log
            let changed = Set(previousLog.keys).symmetricDifference(habit.log.keys)
                .union(previousLog.keys.filter { previousLog[$0] != habit.log[$0] })
            let components = changed.compactMap { key -> DateComponents? in
                guard let date = DayKey.date(from: key, calendar: calendar) else { return nil }
                return calendar.dateComponents([.era, .year, .month, .day], from: date)
            }
            if !components.isEmpty {
                view.reloadDecorations(forDateComponents: components, animated: true)
            }
        }
        guard let selection = view.selectionBehavior as? UICalendarSelectionMultiDate
        else { return }
        // Vergleich über TAGE, nicht über `DateComponents`-Instanzen: die
        // Selection liefert ihre eigenen Instanzen (andere Felder gesetzt),
        // und ein Instanzvergleich würde hier bei jedem Durchlauf „ungleich"
        // sagen und die Auswahl im Kreis neu setzen.
        if dayKeys(selection.selectedDates) != dayKeys(dates) {
            selection.setSelectedDates(Array(dates), animated: false)
        }
    }

    private func dayKeys(_ components: any Collection<DateComponents>) -> Set<String> {
        Set(components.compactMap { calendar.date(from: $0) }
            .map { DayKey.key(for: $0, calendar: calendar) })
    }

    final class Coordinator: NSObject, UICalendarSelectionMultiDateDelegate,
                             UICalendarViewDelegate {
        var parent: BackfillCalendar
        /// Der Log-Stand, für den die Dekorationen zuletzt geladen wurden —
        /// die Vergleichsbasis von `updateUIView`.
        var decoratedLog: [String: Int] = [:]

        init(_ parent: BackfillCalendar) { self.parent = parent }

        // MARK: Dekorationen

        /// Der Punkt unter einem Tag: WAS an diesem Tag schon steht, in den
        /// Farben, in denen es auch im Jahresraster steht. Leerer Tag: kein
        /// Punkt. Das Mapping selbst ist reine Rechnung (`Backfill
        /// .decoration`, getestet); hier wird nur noch Farbe aufgelöst.
        func calendarView(_ calendarView: UICalendarView,
                          decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let date = parent.calendar.date(from: dateComponents) else { return nil }
            let key = DayKey.key(for: date, calendar: parent.calendar)
            guard let decoration = Backfill.decoration(habit: parent.habit, day: key,
                                                       calendar: parent.calendar)
            else { return nil }
            return .default(color: Self.color(level: decoration.level,
                                              style: parent.style),
                            size: .medium)
        }

        /// Dynamische Farbe zur Rampenstufe: hell/dunkel entscheidet die
        /// Trait-Collection des Kalenders SELBST — der Punkt wechselt beim
        /// Schema-Wechsel mit, ohne dass jemand neu lädt. Dieselbe
        /// Stufenlogik wie `Theme.level` (−1 = Verneinungsfarbe), nur als
        /// `UIColor`, weil `UICalendarView` kein SwiftUI spricht.
        static func color(level: Int, style: PaletteStyle) -> UIColor {
            UIColor { trait in
                let dark = trait.userInterfaceStyle == .dark
                let hex = level == Habit.Answer.declinedLevel
                    ? style.negative(dark: dark)
                    : style.ramp(dark: dark)[max(0, min(4, level))]
                return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                               green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255,
                               alpha: 1)
            }
        }

        /// Beide Richtungen schreiben DIESELBE Wahrheit zurück: den ganzen
        /// Stand der Selection — kein Einfügen/Entfernen von Hand, das mit
        /// ungleichen `DateComponents`-Instanzen danebengreifen könnte.
        func multiDateSelection(_ selection: UICalendarSelectionMultiDate,
                                didSelectDate dateComponents: DateComponents) {
            parent.dates = Set(selection.selectedDates)
        }

        func multiDateSelection(_ selection: UICalendarSelectionMultiDate,
                                didDeselectDate dateComponents: DateComponents) {
            parent.dates = Set(selection.selectedDates)
        }
    }
}
