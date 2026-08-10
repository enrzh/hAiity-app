import SwiftUI

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

    @Environment(\.palettes) private var palettes
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.calendar) private var calendar

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
        multi ? Backfill.setActions(habit: habit) : Backfill.actions(for: state)
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
        .frame(maxWidth: 360)
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
        if multi {
            // Zurück auf einen Tag: der JÜNGSTE der Auswahl gewinnt — er ist
            // der, den man zuletzt im Blick hatte.
            if let latest = selectedKeys.last { day = latest }
            multi = false
        } else {
            dates = [calendar.dateComponents([.era, .year, .month, .day],
                                             from: DayKey.date(from: day, calendar: calendar)
                                                ?? Date())]
            multi = true
        }
    }

    /// Der Kalender. Die Spanne kommt aus `Backfill` — die Zukunft ist damit
    /// gar nicht erst antippbar, und der älteste wählbare Tag ist derselbe,
    /// den auch das Raster noch zeigt.
    ///
    /// Ab den Accessibility-Größen wird aus dem Kalenderblatt ein
    /// zusammengeklapptes Feld: der grafische Picker skaliert seine sieben
    /// Spalten nicht mit und schneidet die Ziffern sonst ab.
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
                .background(action.kind == .clear
                            ? AnyShapeStyle(Color(.tertiarySystemFill))
                            : AnyShapeStyle(Theme.accentFill(palettes.style(for: habit))),
                            in: Capsule())
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.4)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
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
