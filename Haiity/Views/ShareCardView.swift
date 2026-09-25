import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Teilbares Bild eines Habits: Name, Emoji, Serie, 26-Wochen-Raster und
/// dezente Wortmarke. Bewusst OHNE ScrollView, damit ImageRenderer das
/// komplette Raster zeichnet; Farben explizit, damit das Bild unabhängig
/// vom Rendering-Kontext dem aktuellen Farbschema entspricht.
struct ShareCardView: View {
    let habit: Habit
    let scheme: ColorScheme
    /// Die AUFGELÖSTE Palette dieses Habits — explizit übergeben statt aus
    /// der Umgebung gelesen: ImageRenderer zeichnet außerhalb des View-Baums,
    /// die Umgebung des aufrufenden Bildschirms kommt hier nicht an. Aufgelöst
    /// wird beim Aufrufer, wo die eigenen Paletten bekannt sind.
    var palette: PaletteStyle = .default
    var weeks: Int = 26

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if !habit.emoji.isEmpty { Text(habit.emoji).font(.title2) }
                Text(habit.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("🔥 \(habit.streak())")
                    .font(.headline.monospacedDigit())
            }
            grid
            HStack {
                Text(String(localized: "\(habit.checkInCount()) Tage insgesamt"))
                    .font(.caption)
                Spacer()
                Text("hAiity")
                    .font(.caption.weight(.semibold))
                    .opacity(0.45)
            }
            .foregroundStyle(secondaryColor)
        }
        .padding(20)
        .foregroundStyle(primaryColor)
        .background(backgroundColor)
        .environment(\.colorScheme, scheme)
    }

    // Explizite Farben — dynamische Systemfarben lösen im ImageRenderer
    // nicht zuverlässig nach dem gewünschten Schema auf.
    private var backgroundColor: Color {
        scheme == .dark ? Color(red: 0.05, green: 0.07, blue: 0.09) : .white
    }
    private var primaryColor: Color { scheme == .dark ? .white : .black }
    private var secondaryColor: Color { scheme == .dark ? Color(white: 0.65) : Color(white: 0.45) }

    private var grid: some View {
        let snapshot = GridCalendar.snapshot(habit: habit, weeks: weeks, today: DayKey.today())
        return HStack(alignment: .top, spacing: gap) {
            ForEach(Array(snapshot.keys.enumerated()), id: \.offset) { wi, column in
                VStack(spacing: gap) {
                    ForEach(0..<GridCalendar.rows, id: \.self) { r in
                        RoundedRectangle(cornerRadius: CornerRadius.pixel, style: .continuous)
                            .fill(Theme.level(snapshot.levels[wi][r],
                                              dark: scheme == .dark,
                                              palette: palette))
                            .opacity(column[r] == nil ? 0.35 : 1)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        // Chronologie wird nie gespiegelt — wie beim Contribution-Grid.
        .environment(\.layoutDirection, .leftToRight)
    }
}

enum ShareCard {
    /// Rendert die Karte mit 3-facher Skalierung — scharf genug für
    /// Messenger und Social. Muss auf dem Main-Thread laufen (ImageRenderer).
    @MainActor
    static func render(habit: Habit,
                       scheme: ColorScheme,
                       palette: PaletteStyle = .default) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(habit: habit,
                                                            scheme: scheme,
                                                            palette: palette))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Transferable-Hülle, die das Bild erst beim tatsächlichen Teilen rendert —
/// so kostet der Menüpunkt "Als Bild teilen" beim bloßen Anzeigen nichts.
struct HabitShareImage: Transferable {
    let habit: Habit
    let dark: Bool
    var palette: PaletteStyle = .default

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            await MainActor.run {
                ShareCard.render(habit: item.habit,
                                 scheme: item.dark ? .dark : .light,
                                 palette: item.palette)?
                    .pngData() ?? Data()
            }
        }
        .suggestedFileName("haiity-card.png")
    }
}
