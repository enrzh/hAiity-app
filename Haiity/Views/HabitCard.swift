import SwiftUI

/// Habit-Karte, seit v3 umgedreht: in der Fläche steckt NUR noch das Raster
/// (samt Monatsmarken). Name, Emoji, Nebendaten, der Heute-Knopf und das Menü
/// stehen darüber nackt auf dem App-Hintergrund — das Raster ist der Held,
/// der Rest ist Beschriftung und braucht kein eigenes Kärtchen.
///
/// Die Kopfzeile ist EINE Zeile:
///
///     📚  Lesen   🔔 19:00  🔥 12            ✓ Erledigt   ⋯
///     └ Name zuerst ┘└ Nebendaten sekundär ┘  └ Aktion ┘  └ Menü ┘
///
/// Erinnerung und Serie sind Nebendaten und stehen deshalb als kleine
/// Symbol-Zahl-Paare direkt hinter dem Namen — auf der Grundlinie des Namens,
/// in `.secondary`. Sie bekommen KEINE eigene Zeile: eine zweite Zeile nur
/// für „🔔 19:00" hat die Karte früher schief aussehen lassen und Karten mit
/// und ohne Erinnerung unterschiedlich hoch gemacht.
///
/// `collapsed` kommt vom Scroll-Zustand der Liste (ContentView misst ihn aus
/// den Zeilenpositionen): beim Scrollen zieht sich der Kopf auf den linken
/// Namen zusammen — Nebendaten weg, Name und Knopf eine Stufe kleiner, und
/// die Zeile wird flacher (44 -> 32 pt), samt der Abstände darum. Ein Kopf,
/// der beim Scrollen seine ausgeklappte Höhe behält, steht als leerer Kasten
/// über dem Raster; genau das war die Rückmeldung. Der Preis: die Zeilen
/// ändern beim Umschalten ihre Höhe und schieben einander — die Messung in
/// `ChromeScroll` setzt dafür kurz aus (Nachlaufsperre).
struct HabitCard: View {
    let habit: Habit
    /// Zusammengezogener Kopf (beim Scrollen). Standard `false`, damit
    /// Vorschauen und Tests die Karte ohne Scroll-Kontext bauen können.
    var collapsed: Bool = false
    let onToggleDay: (String) -> Void
    let onIncrement: () -> Void
    let onClear: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Klammert Pille und verschmolzenen Zustand zusammen, damit das eine ins
    /// andere fliegt statt zu blinken.
    @Namespace private var doneNamespace
    private static let doneID = "done"

    private var today: String { DayKey.today() }
    private var doneToday: Bool { GoalEngine.dayCounts(habit: habit, day: today) }

    /// Höhe der Kopfzeile. Ausgeklappt volle Trefferfläche, zusammengezogen
    /// deutlich flacher — der Kopf soll beim Scrollen nicht als leerer Kasten
    /// über dem Raster stehen bleiben. Als Frame-Höhe (nicht als
    /// Zeilen-Inset) gesetzt, damit der Wert im Übergang INTERPOLIERT.
    private var headerHeight: CGFloat { collapsed ? 32 : Theme.Metrics.hit }

    /// Abstand Kopf -> eigenes Raster. Klein und absichtlich: der Kopf
    /// gehört zur Fläche DARUNTER.
    private var innerGap: CGFloat { collapsed ? 4 : Theme.Metrics.gap }

    /// Abstand zur nächsten Karte — immer ein Vielfaches des inneren
    /// Abstands, sonst liest sich der freistehende Kopf als Fußzeile der
    /// vorigen Karte statt als Überschrift der eigenen.
    private var outerGap: CGFloat { collapsed ? 12 : Theme.Metrics.gutter }

    var body: some View {
        VStack(alignment: .leading, spacing: innerGap) {
            header
            grid
        }
        // Der Zeilenabstand steckt bewusst HIER und nicht in `listRowInsets`:
        // Insets springen beim Umschalten, ein Padding wird animiert.
        .padding(.top, 4)
        .padding(.bottom, outerGap)
        // `.contain` ist hier Pflicht, nicht Deko: ein Identifier auf einem
        // Container ohne diese Angabe faltet den Teilbaum zu EINEM Element
        // zusammen — "check-today" und "edit-habit" verschwinden dann aus
        // dem Baum und sind in XCUITest nicht mehr adressierbar. Als
        // Container bleibt die Karte selbst auffindbar UND ihre Knöpfe.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habit-card")
    }

    // MARK: – Raster in der Fläche

    /// Das Einzige, was noch Karte ist. Das Kontextmenü hängt hier und nicht
    /// am ganzen Block: nur diese Fläche hat eine Form, aus der iOS eine
    /// saubere Vorschau schneiden kann.
    private var grid: some View {
        ContributionGrid(habit: habit, onToggle: onToggleDay)
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                             style: .continuous))
            .contextMenu {
                ShareLink(item: HabitShareImage(habit: habit, dark: scheme == .dark, palette: palettes.style(for: habit)),
                          preview: SharePreview(habit.name)) {
                    Label(String(localized: "Als Bild teilen"), systemImage: "square.and.arrow.up")
                }
                Button(action: onEdit) {
                    Label(String(localized: "Bearbeiten"), systemImage: "pencil")
                }
                Button(action: onArchive) {
                    Label(String(localized: "Archivieren"), systemImage: "archivebox")
                }
            }
    }

    // MARK: – Kopf auf nacktem Grund

    /// Ab den Accessibility-Größen bricht die Zeile um: der Name bekommt die
    /// volle Breite, Nebendaten und Knöpfe rutschen darunter. In einer Zeile
    /// bliebe bei XXL nur noch "La…" vom Habit-Namen übrig.
    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                nameRun
                HStack(spacing: Theme.Metrics.gap) {
                    Spacer(minLength: 0)
                    todayButton
                    editButton
                }
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
        } else {
            HStack(spacing: Theme.Metrics.gap) {
                nameRun
                Spacer(minLength: Theme.Metrics.gap)
                // Zusammengezogen bleiben NUR Name (mit verschmolzenem
                // Heute-Zustand) und die drei Punkte.
                if !collapsed { todayButton }
                editButton
            }
            .frame(height: headerHeight)
            // Auf die Innenkante der Rasterfläche ausgerichtet: Name und
            // erste Rasterspalte stehen in EINER Flucht.
            .padding(.horizontal, Theme.Metrics.cardPadding)
        }
    }

    /// Name zuerst, Nebendaten dahinter — auf DERSELBEN Schriftgrundlinie,
    /// nicht auf gleicher Kastenmitte. Deshalb `.firstTextBaseline` und
    /// Symbole, die als Teil des Textes gesetzt sind.
    ///
    /// Zusammengezogen ist dieser Lauf SELBST der Heute-Knopf: die Pille
    /// wandert per `matchedGeometryEffect` in den Namen und wird dort zum
    /// Häkchen davor (Checkbox) bzw. zum Zähler dahinter (Mengenziel). Damit
    /// bleibt das Abhaken auch beim Scrollen erreichbar — und `check-today`
    /// steht in jedem Zustand genau einmal im Baum.
    private var nameRun: some View {
        Button {
            Theme.Haptics.check()
            if habit.goal.target != nil { onIncrement() } else { onToggleDay(today) }
        } label: {
            nameContent
        }
        .buttonStyle(.plain)
        // Der Knopf steht in BEIDEN Zuständen im Baum und wird ausgeklappt
        // nur stillgelegt. Ein `if collapsed { Button } else { … }` wäre für
        // SwiftUI ein anderer View: der Name würde beim Umschalten
        // übergeblendet (zwei Namen übereinander) statt zu interpolieren.
        .allowsHitTesting(collapsed)
        .accessibilityIdentifier(collapsed ? "check-today" : "habit-name")
        .accessibilityLabel(collapsed ? collapsedActionLabel : habit.name)
        .accessibilityRemoveTraits(collapsed ? [] : .isButton)
    }

    private var nameContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !habit.emoji.isEmpty {
                Text(habit.emoji)
                    .font(collapsed ? .subheadline : .title3)
            }
            Text(habit.name)
                .font(collapsed ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            // Der Zustand steht HINTER dem Namen, nicht davor: sonst rückt
            // ein Häkchen die Namen der abgehakten Karten ein und die Liste
            // fluchtet nicht mehr.
            if collapsed { mergedDone }
            if !collapsed { meta.fixedSize() }
        }
        .contentShape(Rectangle())
    }

    /// Der Heute-Zustand, IM Namen. Kein gefülltes Pillchen mehr: ein Häkchen
    /// vor dem Namen (Checkbox) oder ein Zähler dahinter (Mengenziel), beides
    /// klein und in Akzent- bzw. Sekundärfarbe. Dieselbe
    /// `matchedGeometryEffect`-Kennung wie die Pille — deshalb FLIEGT die
    /// Pille beim Zusammenziehen in den Namen, statt dort auszublenden und
    /// hier neu aufzublitzen.
    @ViewBuilder
    private var mergedDone: some View {
        if let target = habit.goal.target {
            let value = habit.log[today] ?? 0
            Text(verbatim: "\(value)/\(target)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(doneToday
                                 ? AnyShapeStyle(Theme.accentText(palettes.style))
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
        } else {
            Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundStyle(doneToday
                                 ? AnyShapeStyle(Theme.accentText(palettes.style))
                                 : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
        }
    }

    private var collapsedActionLabel: String {
        if let target = habit.goal.target {
            return String(localized: "Heute: \(habit.log[today] ?? 0) von \(target)")
        }
        return doneToday ? String(localized: "✓ Erledigt") : String(localized: "Heute")
    }

    /// Erinnerung und Serie. Beide nur, wenn sie etwas zu sagen haben: eine
    /// Serie von 0 ist keine Serie, und ohne Erinnerung fehlt die Glocke
    /// ersatzlos — nichts rutscht dadurch.
    @ViewBuilder
    private var meta: some View {
        let streak = habit.streak()
        if habit.reminderMinutes != nil || streak > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.gap) {
                if let time = reminderText {
                    metaItem("bell", time,
                             label: String(localized: "Erinnerung um \(time)"))
                }
                if streak > 0 {
                    metaItem("flame.fill", "\(streak)",
                             label: String(localized: "Serie: \(streak) Tage"))
                }
            }
            .padding(.leading, 2)
            .transition(.opacity)
        }
    }

    /// Symbol und Zahl als EIN Textlauf — so sitzt das Glyph automatisch auf
    /// der Grundlinie der Ziffern statt auf der Mitte seines Kastens.
    private func metaItem(_ symbol: String, _ value: String, label: String) -> some View {
        (Text(Image(systemName: symbol)) + Text(verbatim: " \(value)"))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
    }

    /// Heute-Kontrolle im ausgeklappten Zustand: Checkbox toggelt, Mengenziel
    /// zählt hoch. Zusammengezogen gibt es diese Pille nicht mehr — sie ist
    /// dann im Namen aufgegangen (siehe `mergedDone`).
    @ViewBuilder
    private var todayButton: some View {
        if let target = habit.goal.target {
            let value = habit.log[today] ?? 0
            Button {
                Theme.Haptics.check()
                onIncrement()
            } label: {
                pill("\(value)/\(target)", monospaced: true)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive, action: onClear) {
                    Label(String(localized: "Zurücksetzen"), systemImage: "arrow.counterclockwise")
                }
            }
            .accessibilityLabel(String(localized: "Heute: \(value) von \(target)"))
            .accessibilityIdentifier("check-today")
        } else {
            Button {
                Theme.Haptics.check()
                onToggleDay(today)
            } label: {
                pill(doneToday ? String(localized: "✓ Erledigt") : String(localized: "Heute"))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneToday
                                ? String(localized: "✓ Erledigt")
                                : String(localized: "Heute"))
            .accessibilityIdentifier("check-today")
        }
    }

    /// Die Pille ist SICHTBAR klein, die Trefferfläche trotzdem so hoch wie
    /// die Kopfzeile.
    private func pill(_ text: String, monospaced: Bool = false) -> some View {
        let base = Font.subheadline.weight(.semibold)
        return Text(verbatim: text)
            .font(monospaced ? base.monospacedDigit() : base)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(doneToday ? Theme.accentFill(palettes.style) : Color(.tertiarySystemFill),
                        in: Capsule())
            .foregroundStyle(doneToday ? .white : .primary)
            .matchedGeometryEffect(id: Self.doneID, in: doneNamespace)
            .frame(height: headerHeight)
            .contentShape(Rectangle())
    }

    /// Das Glyph steht an der TRAILING-Kante seiner 44er-Trefferfläche —
    /// damit fluchtet es mit der rechten Innenkante des Rasters, während der
    /// Finger die vollen 44 pt bekommt.
    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "ellipsis")
                .font(collapsed ? .caption : .footnote)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Metrics.hit, height: headerHeight,
                       alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(habit.name) bearbeiten"))
        .accessibilityIdentifier("edit-habit")
    }

    private var reminderText: String? {
        guard let m = habit.reminderMinutes else { return nil }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
