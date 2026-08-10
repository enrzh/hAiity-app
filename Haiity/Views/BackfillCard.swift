import SwiftUI
import UIKit

/// „Nacharbeiten": die Karte, in der ein VERGANGENER Tag nachgetragen wird.
///
/// Sie steht in der MITTE, nicht als Blatt von unten. Zwei Gründe: sie ist
/// kurz (Titel, Kalender, eine Zeile Status, ein, zwei Knöpfe) und sie ist
/// ein Zwischenschritt, kein Ort — ein Blatt, das über die halbe App fährt,
/// behauptet mehr Gewicht, als der Vorgang hat. Und: unten steht die Leiste
/// mit dem Rückgängig-Toast, und genau der muss neben ihr erreichbar bleiben.
///
/// Die Karte SCHREIBT NICHT SELBST. Sie meldet „schreib diesen Wert an diesen
/// Tag" nach oben (`onWrite`) — dort läuft der Schreibvorgang durch dieselbe
/// Stelle wie jedes andere Abhaken, inklusive des exakten Rückgängig
/// (`ContentView.mutate`).
struct BackfillCard: View {
    /// Der LEBENDE Habit aus dem Store: nach einem Schreibvorgang zeigt die
    /// Statuszeile sofort den neuen Stand, ohne die Karte zu schließen.
    let habit: Habit
    /// Gewählter Tag als Tagesschlüssel. Liegt beim Aufrufer, damit ein
    /// zweiter Zellentipp die offene Karte umstellt statt sie zu ignorieren.
    @Binding var day: String
    /// (Tage, Wert) — `nil` als Wert entfernt die Einträge. IMMER eine
    /// Liste, auch für einen Tag: der Aufrufer schreibt einen Vorgang, nicht
    /// n Vorgänge, und macht daraus EIN Zurück.
    let onWrite: ([String], Int?) -> Void
    let onClose: () -> Void

    /// Mehrfachauswahl an? Der Zustand lebt in der Karte: er ist eine
    /// Arbeitsweise für diesen einen Vorgang, keine Einstellung.
    @State private var multi = false
    /// Die gewählten Tage im Mehrfach-Modus. `MultiDatePicker` spricht
    /// `DateComponents`; umgerechnet wird an genau einer Stelle
    /// (`selectedKeys`).
    @State private var dates: Set<DateComponents> = []
    /// Sperrklinke für die Höhe des Mehrfach-Kalenders. `MultiDatePicker`
    /// misst sich nach dem ersten Layout noch einmal und wird dabei ein paar
    /// Punkte NIEDRIGER (nachgemessen: 554 -> 551,3 pt) — die Karte zuckte
    /// mit. Die größte je gesehene Höhe bleibt als Mindesthöhe stehen; das
    /// Blatt sitzt oben bündig, und die Karte steht still.
    @State private var multiHeight: CGFloat = 0

    @Environment(\.palettes) private var palettes
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Referenzmaß 100, skaliert mit Dynamic Type: `typeScale / 100` IST der
    /// Faktor, mit dem `.body` gerade wächst. Dieselbe Messtechnik wie im
    /// Jahresraster (`ContributionGrid.labelScale`) — sie sagt die
    /// Schriftgröße, ohne die Trait-Collection nachzubauen.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 100

    private var state: Backfill.DayState { Backfill.state(habit: habit, day: day) }
    private var writable: Bool { Backfill.canWrite(habit: habit, day: day) }

    /// Die gewählten Tage als Tagesschlüssel, aufsteigend. Was der Kalender
    /// nicht in ein echtes Datum auflösen kann, fällt hier schon weg — der
    /// Schreibweg prüft trotzdem noch einmal (siehe `Backfill.canWrite`).
    private var selectedKeys: [String] {
        dates.compactMap { calendar.date(from: $0) }
            .map { DayKey.key(for: $0, calendar: calendar) }
            .sorted()
    }

    private var actions: [Backfill.Action] {
        multi ? Backfill.setActions(habit: habit)
              : Backfill.actions(for: state, kind: habit.kind)
    }

    /// Ist überhaupt etwas zu schreiben?
    private var enabled: Bool {
        multi ? !selectedKeys.isEmpty : writable
    }

    /// Datum und Tagesschlüssel sind zwei Sichten auf DASSELBE — der Picker
    /// spricht `Date`, gespeichert wird der Schlüssel.
    private var selection: Binding<Date> {
        Binding(get: { DayKey.date(from: day, calendar: calendar) ?? Date() },
                set: { day = DayKey.key(for: $0, calendar: calendar) })
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
        // Der Mehrfach-Kalender ist höher als der einzelne, und in den
        // Accessibility-Größen wächst alles noch einmal. `ViewThatFits`
        // nimmt zuerst die ruhige Form (nichts scrollt) und erst dann, wenn
        // es wirklich nicht passt, die scrollende — statt auf einem kleinen
        // Gerät den Knopf unter den Bildschirmrand zu schieben.
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
    }

    private var cardBody: some View {
        VStack(spacing: 14) {
            header
            picker
            status
            actionRow
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
                Text(multi
                     ? String(localized: "Mehrere Tage nachtragen")
                     : String(localized: "Tag nachtragen"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            multiToggle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Der Umschalter oben rechts. Er wechselt nicht die Karte, sondern nur
    /// den Kalender darin — und behält dabei den Tag: wer im
    /// Einzel-Modus den 5. Mai vor sich hatte, findet ihn im Mehrfach-Modus
    /// ausgewählt wieder (und umgekehrt den zuletzt gewählten).
    private var multiToggle: some View {
        Button(action: toggleMulti) {
            Image(systemName: "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(multi
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 34, height: 34)
                .background(multi
                            ? AnyShapeStyle(Theme.accentFill(palettes.style(for: habit)))
                            : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Mehrfachauswahl"))
        .accessibilityValue(multi ? String(localized: "An") : String(localized: "Aus"))
        .accessibilityAddTraits(multi ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("backfill-multi-toggle")
    }

    private func toggleMulti() {
        Theme.Haptics.select()
        let flip = {
            if multi {
                // Zurück auf einen Tag: der JÜNGSTE der Auswahl gewinnt — er
                // ist der, den man zuletzt im Blick hatte.
                if let latest = selectedKeys.last { day = latest }
                multi = false
            } else {
                dates = [calendar.dateComponents([.era, .year, .month, .day],
                                                 from: DayKey.date(from: day, calendar: calendar)
                                                    ?? Date())]
                multi = true
            }
        }
        // Der Mehrfach-Kalender ist deutlich höher als der einzelne — die
        // Karte ÄNDERT hier ihre Größe, und zwar absichtlich. Ein Sprung
        // ohne Übergang sähe aus wie das Zucken, das diese Karte sonst
        // überall unterbindet; also derselbe kurze Übergang wie beim Öffnen
        // (`ContentView.withCardAnimation`).
        if reduceMotion { flip() } else { withAnimation(.snappy(duration: 0.22), flip) }
    }

    // MARK: – Maße der Karte
    //
    // Die Karte hat eine BERECHENBARE Breite: gedeckelt auf `maxWidth`, sonst
    // das Fenster minus der beiden Seitenränder. Daraus fällt das Innenmaß —
    // und aus dem Innenmaß die Höhe, die das Kalenderblatt reserviert.

    static let maxWidth: CGFloat = 360

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

    /// Die Höhe, die das Kalenderblatt VORAB bekommt — der Kern der Sache,
    /// siehe `Backfill.calendarHeight`.
    private var calendarHeight: CGFloat {
        Backfill.calendarHeight(width: Self.contentWidth(window: Self.windowWidth()),
                                typeScale: typeScale / 100)
    }

    /// Der Kalender. Die Spanne kommt aus `Backfill` — die Zukunft ist damit
    /// gar nicht erst antippbar, und der älteste wählbare Tag ist derselbe,
    /// den auch das Raster noch zeigt.
    ///
    /// Ab den Accessibility-Größen wird aus dem Kalenderblatt ein
    /// zusammengeklapptes Feld: der grafische Picker skaliert seine sieben
    /// Spalten nicht mit und schneidet die Ziffern sonst ab.
    ///
    /// **Die Höhe wird RESERVIERT, nicht abgewartet.** Der grafische
    /// `DatePicker` ist ein `UIDatePicker` in SwiftUI-Kleidern, und der meldet
    /// beim ERSTEN Layout eine Höhe, der genau eine Wochenzeile fehlt: auf
    /// diesem Gerät 374,7 pt erst nach 324 pt (nachgemessen, Abstand zwischen
    /// beiden Messungen 6 bis 100 ms). Die Karte wächst mit ihrem Inhalt, also
    /// stand sie fünf Bilder lang 50 pt zu niedrig und sprang dann — genau das
    /// „adjusts its size for a split second". Mit einer vorab gerechneten
    /// Mindesthöhe steht die Karte vom ersten Bild an auf ihrem Endmaß.
    @ViewBuilder
    private var picker: some View {
        if multi {
            // Die Mehrfachauswahl macht der Kalender selbst — dieselbe
            // Bildsprache wie der grafische Picker und dieselbe Spanne, also
            // greifen die Grenzen aus `Backfill` unverändert weiter.
            MultiDatePicker(String(localized: "Tage"),
                            selection: $dates,
                            in: Backfill.dateRangeExclusive(habit: habit, calendar: calendar))
                .labelsHidden()
                // Oben bündig in der eigenen Reserve, und die wächst nur:
                // misst der Picker sich nach dem ersten Layout kleiner
                // (siehe `multiHeight`), hält die Sperrklinke die Karte auf
                // ihrem Maß.
                .frame(minHeight: max(multiHeight, calendarHeight), alignment: .top)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { multiHeight = max(multiHeight, g.size.height) }
                        .onChange(of: g.size.height) { _, h in
                            multiHeight = max(multiHeight, h)
                        }
                })
                .accessibilityIdentifier("backfill-date-picker")
        } else if typeSize.isAccessibilitySize {
            DatePicker(String(localized: "Tag"),
                       selection: selection,
                       in: Backfill.dateRange(habit: habit, calendar: calendar),
                       displayedComponents: .date)
                .accessibilityIdentifier("backfill-date-picker")
        } else {
            DatePicker(String(localized: "Tag"),
                       selection: selection,
                       in: Backfill.dateRange(habit: habit, calendar: calendar),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                // `minHeight`, nicht `height`: liegt die Reserve einmal
                // daneben, wächst das Blatt wie bisher weiter — es wird nie
                // abgeschnitten. Oben bündig: fällt die Reserve ein, zwei
                // Punkte größer aus als das Blatt, bleibt der Rest UNTEN als
                // schmaler Rand, statt das Blatt beim Nachmessen zu
                // verschieben.
                .frame(minHeight: calendarHeight, alignment: .top)
                .accessibilityIdentifier("backfill-date-picker")
        }
    }

    /// Die lebende Statuszeile: welcher Tag (bzw. wie viele), und wie es dort
    /// GERADE steht. Sie ist der einzige Ort, an dem man vor dem Schreiben
    /// sieht, was eine Aktion tatsächlich ändern wird — im Mehrfach-Modus
    /// steht deshalb dabei, wie viele der gewählten Tage schon zählen.
    private var status: some View {
        let selection = Backfill.selection(habit: habit, days: Set(selectedKeys))
        let highlighted = multi ? selection.done > 0 : state.counts
        return Text(multi
                    ? Backfill.selectionLine(habit: habit, days: Set(selectedKeys),
                                             calendar: calendar)
                    : Backfill.statusLine(habit: habit, day: day, calendar: calendar))
            .font(.subheadline)
            .foregroundStyle(highlighted
                             ? AnyShapeStyle(Theme.accentText(palettes.style(for: habit)))
                             : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            // IMMER eine Zeile. Der Text wechselt mit jeder Tageswahl und mit
            // dem Mehrfach-Modus; dürfte er umbrechen, änderte sich mitten im
            // Vorgang die Höhe der KARTE — dieselbe Art Sprung, die oben am
            // Kalenderblatt behoben ist. Lieber eine Spur kleiner gesetzt als
            // eine Karte, die beim Tippen die Größe wechselt. (In den
            // Accessibility-Größen steht statt des Kalenderblatts ohnehin ein
            // zusammengeklapptes Feld, und die Karte scrollt.)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("backfill-status")
    }

    /// EINE Liste, kein Kippknopf. Was hier steht, entscheidet `Backfill`
    /// aus dem Zustand des Tages — heute ein bis zwei Einträge, mit der
    /// Habit-Art „Ja/Nein" werden es mehr, ohne dass diese Ansicht sich
    /// ändern muss.
    private var actionRow: some View {
        HStack(spacing: Theme.Metrics.gap) {
            ForEach(actions) { action in
                Button {
                    onWrite(multi ? selectedKeys : [day], action.value)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metrics.hit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(action.kind == .clear
                                 ? AnyShapeStyle(HierarchicalShapeStyle.primary)
                                 : AnyShapeStyle(Color.white))
                .background(fill(for: action), in: Capsule())
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.4)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
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
}
