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
/// **Zwei Arbeitsweisen, EINE Einstellung (Mehr-Tafel, `Backfill.Mode`).**
///  * **Malen:** oben liegt eine Pinselzeile (Erledigt / Ja / Nein / Menge /
///    Leeren — je nach Habit-Art), und jeder angetippte Tag bekommt sofort
///    den Pinselwert. Ein zweiter Tipp auf denselben Tag stellt seinen
///    ALTEN Wert wieder her — nicht bloß leer.
///  * **Auswählen:** erst Tage sammeln, dann EINE Aktion auf alle anwenden.
///    Die Leiste kennt jetzt jeden Zielzustand der Art (auch „Nein" und die
///    Menge); die Auswahl bleibt nach der Aktion stehen, damit die nächste
///    gleich folgen kann.
///
/// Die Karte SCHREIBT NICHT SELBST. Sie meldet „schreib diesen Wert an diese
/// Tage" (`onWrite`) bzw. „stell diese Vorwerte wieder her" (`onRestore`)
/// nach oben — dort läuft alles durch dieselbe Stelle wie jedes andere
/// Abhaken, inklusive EINES Rückgängig pro Griff (`ContentView`).
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
    /// (Tag, Vorwert) je Tag — der EXAKTE Rückbau eines gemalten Tages. Ein
    /// einheitlicher Wert reicht hier nicht: drei abgemalte Tage können drei
    /// verschiedene Vorwerte haben.
    let onRestore: ([(day: String, value: Int?)]) -> Void
    let onClose: () -> Void

    /// Die Arbeitsweise ist eine EINSTELLUNG (siehe `Backfill.Mode`), kein
    /// Zustand der Karte — dieselbe Ablage wie die Statistik-Karten
    /// (App-Group-Defaults, nicht data.json).
    @AppStorage(Backfill.Mode.storageKey,
                store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var modeRaw = Backfill.Mode.paint.rawValue
    private var mode: Backfill.Mode { .resolve(modeRaw) }

    /// Die gewählten bzw. angemalten Tage. `MultiDatePicker` spricht
    /// `DateComponents`; umgerechnet wird an genau einer Stelle
    /// (`selectedKeys`).
    @State private var dates: Set<DateComponents> = []
    /// Malen: je angemaltem Tag der Wert, der VOR dem Pinsel dort stand
    /// (nil = kein Eintrag). Der zweite Tipp stellt genau ihn wieder her.
    @State private var painted: [String: Int?] = [:]
    /// Der gewählte Pinsel als Kennungs-Stamm (`Backfill.Brush.id`). Leer =
    /// der positive Standardpinsel der Habit-Art — so braucht es keinen
    /// onAppear, der der Art hinterherläuft.
    @State private var brushId = ""
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

    /// Mengenwert für Pinsel und Auswahl-Aktion: der Steller, sonst das
    /// Tagesziel.
    private var effectiveAmount: Int {
        amount > 0 ? amount : max(1, habit.recurrence.target ?? 1)
    }

    /// Der wirksame Pinsel — Kennung plus Menge, gegen die Habit-Art
    /// aufgelöst. Ein gespeicherter Stamm, der zur Art nicht passt (die gibt
    /// es in EINER Kartensitzung nicht, aber die Auflösung soll es nicht
    /// glauben müssen), fällt auf den Standard zurück.
    private var brush: Backfill.Brush {
        let known = Backfill.Brush.brushes(for: habit.kind, amount: effectiveAmount)
        return known.first { $0.id == brushId } ?? known[0]
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
        ZStack {
            scrim
            card
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
        // Die Karte hält sich von der Leiste frei: sie liegt UNTER dem Chrom,
        // und ein „Fertig", das hinter dem Umschalter klebt, wäre nicht
        // erreichbar.
        .padding(.bottom, Theme.Metrics.control + 2 * Theme.Metrics.gap)
        // Die Karte ist modal: VoiceOver soll nicht durch sie hindurch in die
        // Liste greifen, die dahinter noch steht.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(String(localized: "Nacharbeiten: \(habit.name)"))
        .accessibilityIdentifier("backfill-card")
        .onAppear(perform: seed)
        .onChange(of: dates) { old, new in datesChanged(from: old, to: new) }
    }

    /// Beide Arbeitsweisen haben GENAU EINE Bedienzeile fester Höhe — beim
    /// Malen über dem Kalender (der Pinsel kommt vor dem Tippen), beim
    /// Auswählen darunter (die Aktion kommt nach dem Sammeln). Gleiche
    /// Zeilenhöhe, gleiche Teile: die Karte ist in beiden Arbeitsweisen und
    /// für jede Habit-Art gleich hoch — kein Größensprung beim Umstellen.
    private var cardBody: some View {
        VStack(spacing: 14) {
            header
            if mode == .paint { brushRow }
            picker
            status
            if mode == .select { actionRow }
            closeButton
        }
        .padding(Theme.Metrics.gutter)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !habit.emoji.isEmpty { Text(habit.emoji).font(.title3) }
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(mode == .paint
                     ? String(localized: "Tage antippen und eintragen")
                     : String(localized: "Tage auswählen, dann eintragen"))
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

    /// Feste Höhe der Bedienzeile (Pinsel bzw. Aktionen) — für JEDE
    /// Habit-Art dieselbe, sonst wäre die Karte bei „Menge" höher als bei
    /// „Ja/Nein".
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

    /// Der Kalender — in BEIDEN Arbeitsweisen der `MultiDatePicker`: beim
    /// Malen ist die Auswahl die Leinwand (jeder Tag darin trägt den
    /// Pinselwert), beim Auswählen ist sie die Sammlung. Die Spanne kommt aus
    /// `Backfill` — die Zukunft ist damit gar nicht erst antippbar, und der
    /// älteste wählbare Tag ist derselbe, den auch das Raster noch zeigt.
    ///
    /// **Die Höhe wird RESERVIERT, nicht abgewartet** (`calendarHeight`), und
    /// die Sperrklinke `multiHeight` hält die größte je gemessene Höhe fest —
    /// zusammen steht die Karte vom ersten Bild an auf ihrem Endmaß.
    private var picker: some View {
        BackfillCalendar(dates: $dates,
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

    /// Die lebende Statuszeile. Malen: wie viele Tage der Griff schon
    /// geändert hat. Auswählen: wie viele Tage gewählt sind und wie viele
    /// davon schon zählen — der einzige Ort, an dem man VOR dem Schreiben
    /// sieht, was eine Aktion tatsächlich ändern wird.
    private var status: some View {
        let selection = Backfill.selection(habit: habit, days: Set(selectedKeys))
        let highlighted = mode == .paint ? !painted.isEmpty : selection.done > 0
        return Text(mode == .paint
                    ? Backfill.paintText(painted: painted.count)
                    : Backfill.selectionLine(habit: habit, days: Set(selectedKeys),
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

    // MARK: – Malen

    /// Die Pinselzeile: ein Pinsel ist AUSGEWÄHLT (gefüllt), die anderen
    /// stehen daneben. Bei „Menge" ist der Pinsel selbst ein Steller.
    private var brushRow: some View {
        HStack(spacing: Theme.Metrics.gap) {
            ForEach(Backfill.Brush.brushes(for: habit.kind, amount: effectiveAmount)) { b in
                if case .amount = b {
                    amountBrush
                } else {
                    brushButton(b)
                }
            }
        }
        .frame(height: Self.controlRowHeight)
    }

    private func brushButton(_ b: Backfill.Brush) -> some View {
        let selected = brush.id == b.id
        return Button {
            Theme.Haptics.select()
            brushId = b.id
        } label: {
            Label(b.title, systemImage: b.systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: Self.controlRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? brushForeground(b) : AnyShapeStyle(HierarchicalShapeStyle.primary))
        .background(selected ? brushFill(b) : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? .clear : Color(.separator).opacity(0.5)))
        .accessibilityLabel(b.title)
        .accessibilityValue(selected
                            ? String(localized: "Ausgewählt")
                            : String(localized: "Nicht ausgewählt"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(b.accessibilityIdentifier)
    }

    /// Der Mengen-Pinsel: Minus, Stand, Plus in EINER Kapsel. Er ist immer
    /// zugleich der aktive Pinsel, sobald man ihn anfasst — wer die Menge
    /// stellt, will sie auch malen.
    private var amountBrush: some View {
        let b = Backfill.Brush.amount(effectiveAmount)
        let selected = brush.id == b.id
        return HStack(spacing: 0) {
            stepButton("minus", enabled: effectiveAmount > 1) { step(-1) }
                .accessibilityLabel(String(localized: "Menge verringern"))
                .accessibilityIdentifier("backfill-amount-minus")
            Button {
                Theme.Haptics.select()
                brushId = b.id
            } label: {
                Text(b.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.controlRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Menge: \(effectiveAmount)"))
            .accessibilityValue(selected
                                ? String(localized: "Ausgewählt")
                                : String(localized: "Nicht ausgewählt"))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier(b.accessibilityIdentifier)
            stepButton("plus", enabled: effectiveAmount < Habit.Answer.maxCount) { step(1) }
                .accessibilityLabel(String(localized: "Menge erhöhen"))
                .accessibilityIdentifier("backfill-amount-plus")
        }
        .foregroundStyle(selected ? brushForeground(b) : AnyShapeStyle(HierarchicalShapeStyle.primary))
        .background(selected ? brushFill(b) : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? .clear : Color(.separator).opacity(0.5)))
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

    /// Stellen wählt zugleich den Mengen-Pinsel — und ändert NIE bereits
    /// gemalte Tage: der Steller gilt für die nächsten Tipps.
    private func step(_ delta: Int) {
        Theme.Haptics.select()
        amount = min(Habit.Answer.maxCount, max(1, effectiveAmount + delta))
        brushId = "amount"
    }

    private func brushForeground(_ b: Backfill.Brush) -> AnyShapeStyle {
        if case .clear = b { return AnyShapeStyle(HierarchicalShapeStyle.primary) }
        return AnyShapeStyle(Color.white)
    }

    /// Der Pinsel trägt die Farbe seiner Bedeutung: „Nein" in der
    /// Verneinungsfarbe dieses Habits — derselben, in der der Tag gleich im
    /// Raster steht (dieselbe Zusage wie bei den Aktionen).
    private func brushFill(_ b: Backfill.Brush) -> AnyShapeStyle {
        let style = palettes.style(for: habit)
        switch b {
        case .clear:    return AnyShapeStyle(Color(.systemFill))
        case .declined: return AnyShapeStyle(Theme.color(style.negative(dark: scheme == .dark)))
        default:        return AnyShapeStyle(Theme.accentFill(style))
        }
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

    private var closeButton: some View {
        Button(action: onClose) {
            Text(String(localized: "Fertig"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("backfill-close")
    }

    // MARK: – Tippen im Kalender

    /// Auswählen startet mit dem Tag, an dem die Karte geöffnet wurde — wer
    /// über eine Rasterzelle kam, findet genau sie vorausgewählt. Malen
    /// startet LEER: eine Vorauswahl würde sofort malen, und das hat niemand
    /// getan.
    private func seed() {
        guard mode == .select, dates.isEmpty,
              let date = DayKey.date(from: day, calendar: calendar) else { return }
        dates = [calendar.dateComponents([.era, .year, .month, .day], from: date)]
    }

    /// Malen: jeder NEU gewählte Tag bekommt sofort den Pinselwert; jeder
    /// ABGEWÄHLTE bekommt seinen Vorwert zurück. Auswählen: nichts — dort
    /// schreibt erst die Aktionsleiste.
    private func datesChanged(from old: Set<DateComponents>, to new: Set<DateComponents>) {
        guard mode == .paint else { return }
        let keys = Set(selectedKeys)
        let added = keys.subtracting(painted.keys).sorted()
        let removed = Set(painted.keys).subtracting(keys).sorted()

        if !added.isEmpty {
            let b = brush
            for key in added { painted.updateValue(habit.log[key], forKey: key) }
            onWrite(added, b.value)
            if let only = added.first, added.count == 1 {
                announce(String(localized: "\(Backfill.dayText(only, calendar: calendar)): \(b.title)"))
            }
        }
        if !removed.isEmpty {
            let entries = removed.map { (day: $0, value: painted[$0] ?? nil) }
            for key in removed { painted.removeValue(forKey: key) }
            onRestore(entries)
            if let only = removed.first, removed.count == 1 {
                announce(String(localized: "\(Backfill.dayText(only, calendar: calendar)) wiederhergestellt"))
            }
        }
    }

    /// Gemalte Tage haben im Kalender ihren Auswahlkreis; WAS dort steht,
    /// sagt VoiceOver hinterher — der Systemkalender kennt keine eigenen
    /// Tagesdekorationen, und die Statuszeile zählt für alle Sehenden mit.
    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
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
    let range: ClosedRange<Date>
    let calendar: Calendar

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.availableDateRange = DateInterval(start: range.lowerBound,
                                               end: range.upperBound)
        let selection = UICalendarSelectionMultiDate(delegate: context.coordinator)
        selection.setSelectedDates(Array(dates), animated: false)
        view.selectionBehavior = selection
        // Die Karte reserviert die Höhe selbst (siehe `calendarHeight`);
        // das Blatt soll sich der Breite fügen, nicht die Karte sprengen.
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "backfill-date-picker"
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        context.coordinator.parent = self
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

    final class Coordinator: NSObject, UICalendarSelectionMultiDateDelegate {
        var parent: BackfillCalendar

        init(_ parent: BackfillCalendar) { self.parent = parent }

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
