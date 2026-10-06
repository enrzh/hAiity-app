import PhotosUI
import SwiftUI
import UIKit

/// The crop frame has to match the live screen, not a fixed phone ratio.
/// A missing scene keeps the previous 0.46 fallback so previews still fit.
enum BackgroundCropFrame {
    static func aspect(of screenBounds: CGRect) -> CGFloat {
        guard screenBounds.width > 0, screenBounds.height > 0 else { return 0.46 }
        return screenBounds.width / screenBounds.height
    }

    static var liveScreenAspect: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return aspect(of: scene?.screen.bounds ?? .zero)
    }
}

private struct BackgroundCropSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let preferences: AppearancePreferences
    let onSave: (Double, Double, Double) -> Void
    @State private var focus: CGPoint
    @State private var dragOrigin: CGPoint?
    @State private var zoom: CGFloat
    @State private var zoomOrigin: CGFloat

    init(preferences: AppearancePreferences, onSave: @escaping (Double, Double, Double) -> Void) {
        self.preferences = preferences
        self.onSave = onSave
        let initialZoom = CGFloat(BackgroundImagePlacement.clampedZoom(preferences.backgroundImageZoom))
        _focus = State(initialValue: CGPoint(x: preferences.backgroundImageFocusX,
                                             y: preferences.backgroundImageFocusY))
        _zoom = State(initialValue: initialZoom)
        _zoomOrigin = State(initialValue: initialZoom)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { proxy in
                    if let image = preferences.backgroundImage {
                        let placement = BackgroundImagePlacement.make(
                            imageSize: image.size,
                            containerSize: proxy.size,
                            focusX: Double(focus.x),
                            focusY: Double(focus.y),
                            zoom: Double(zoom))
                        let excess = CGSize(width: max(placement.size.width - proxy.size.width, 0),
                                            height: max(placement.size.height - proxy.size.height, 0))
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: placement.size.width, height: placement.size.height)
                            .offset(x: placement.offset.width,
                                    y: placement.offset.height)
                            .overlay(Color.black.opacity(0.16))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous))
                            .contentShape(Rectangle())
                            .simultaneousGesture(MagnificationGesture().onChanged { value in
                                zoom = CGFloat(BackgroundImagePlacement.clampedZoom(Double(zoomOrigin * value)))
                            }.onEnded { _ in
                                zoomOrigin = zoom
                            })
                            .simultaneousGesture(DragGesture().onChanged { value in
                                if dragOrigin == nil { dragOrigin = focus }
                                let dx = value.translation.width / max(excess.width, 1)
                                let dy = value.translation.height / max(excess.height, 1)
                                let origin = dragOrigin ?? focus
                                focus = CGPoint(x: min(max(origin.x - dx, 0), 1),
                                                y: min(max(origin.y - dy, 0), 1))
                            }.onEnded { _ in
                                dragOrigin = nil
                            })
                    } else {
                        ContentUnavailableView(String(localized: "Kein Bild"),
                                               systemImage: "photo")
                    }
                }
                .aspectRatio(BackgroundCropFrame.liveScreenAspect, contentMode: .fit)
                .id(verticalSizeClass)
                Text(String(localized: "Ziehe das Bild, um den sichtbaren Ausschnitt festzulegen."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(String(localized: "Hintergrund anpassen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern")) {
                        onSave(Double(focus.x), Double(focus.y),
                               BackgroundImagePlacement.clampedZoom(Double(zoom)))
                        dismiss()
                    }
                }
            }
        }
    }
}

extension MoreView {
    private var hasPersistedBackgroundImage: Bool {
        currentAppearance.backgroundImageData != nil
    }

    var appearanceSettings: some View {
        SettingsPage {
                DesignStylePicker(selection: designStyleBinding)
                    .accessibilityIdentifier("appearance-design-picker")
                appearanceSection
                    .padding(currentAppearance.designStyle.cardPadding)
                    .morePanel()
                DisclosureGroup(isExpanded: $showingAppearanceCustomize) {
                    VStack(alignment: .leading, spacing: store.appearancePreferences.designStyle.sectionGap) {
                        materialAppearanceSection
                        morePageRule
                        backgroundControl
                        morePageRule
                        paletteSection
                        morePageRule
                        iconAppearanceSection
                        morePageRule
                        VStack(alignment: .leading, spacing: currentAppearance.designStyle.rowGap * 2) {
                            moreSubsectionLabel(String(localized: "Verhalten"))
                            compactModeSection
                        }
                    }
                    .padding(.top, currentAppearance.designStyle.rowGap * 2)
                } label: {
                    AppSettingsRow(title: String(localized: "Anpassen"),
                                   symbol: "slider.horizontal.3") {
                        EmptyView()
                    }
                }
                .padding(currentAppearance.designStyle.cardPadding)
                .morePanel()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("appearance-customize")
        }
        .safeAreaPadding(.top, currentAppearance.designStyle.cardPadding)
    }

    private var morePageRule: some View {
        Divider()
            .opacity(0.7)
            .padding(.vertical, currentAppearance.designStyle.rowGap)
    }

    private func moreSubsectionLabel(_ title: String) -> some View {
        Text(title)
            .font(currentAppearance.designStyle.sectionTitleFont)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var compactModeSection: some View {
        VStack(alignment: .leading, spacing: currentAppearance.designStyle.rowGap * 2) {
            Toggle(isOn: Binding(
                get: { statsCards.compactMode },
                set: { statsCards.compactMode = $0 })) {
                AppSettingsRow(title: String(localized: "Kompakte Ansicht"),
                               symbol: "rectangle.compress.vertical") {
                    EmptyView()
                }
            }
            .accessibilityIdentifier("compact-mode-toggle")
            Toggle(isOn: Binding(
                get: { statsCards.widgetResetEnabled },
                set: { statsCards.widgetResetEnabled = $0 })) {
                AppSettingsRow(title: String(localized: "Rückgängig in Widgets"),
                               symbol: "arrow.uturn.backward.circle") {
                    EmptyView()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("widget-reset-toggle")
            Toggle(isOn: Binding(
                get: { statsCards.dictateCreateEnabled },
                set: { statsCards.dictateCreateEnabled = $0 })) {
                AppSettingsRow(title: String(localized: "Aus einem Satz anlegen"),
                               detail: String(localized: "Den Knopf auf der Hauptseite zeigen"),
                               symbol: "sparkles") {
                    EmptyView()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dictate-create-toggle")
        }
    }

    // MARK: – Darstellung
    //
    // Erscheinungsbild und Graph-Farbe stehen bewusst in EINEM Abschnitt und
    // trotzdem als zwei getrennte Einstellungen: beides beantwortet „wie
    // sieht die App aus", aber niemand will Hell/Dunkel mitverstellen, nur
    // weil er das Grün loswerden möchte.

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: currentAppearance.designStyle.rowGap * 2 + 2) {
            Menu {
                ForEach(AppearanceSetting.allCases, id: \.self) { option in
                    Button {
                        appearanceBinding.wrappedValue = option
                    } label: {
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if option == store.appearance {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                AppSettingsRow(title: String(localized: "Erscheinungsbild"),
                               detail: store.appearance.displayName,
                               symbol: "circle.lefthalf.filled") {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .accessibilityIdentifier("appearance-picker")
        }
    }

    private var materialAppearanceSection: some View {
        VStack(alignment: .leading, spacing: currentAppearance.designStyle.rowGap * 2 + 2) {
            MaterialPreviewPicker(selection: materialBinding)
                .frame(minHeight: currentAppearance.designStyle.settingsRowHeight,
                       alignment: .leading)
                .accessibilityIdentifier("appearance-material-picker")

            Toggle(isOn: performanceModeBinding) {
                AppSettingsRow(title: String(localized: "Performance-Modus"),
                               symbol: "speedometer") {
                    EmptyView()
                }
            }
            .accessibilityIdentifier("performance-mode-toggle")
        }
    }

    private var iconAppearanceSection: some View {
        VStack(alignment: .leading, spacing: currentAppearance.designStyle.cardPadding + 4) {
            Toggle(isOn: graphShowsMonthLabels) {
                AppSettingsRow(title: String(localized: "Monate anzeigen"),
                               symbol: "calendar") {
                    EmptyView()
                }
            }
            .accessibilityIdentifier("graph-month-labels-toggle")

            Toggle(isOn: matchIconBinding) {
                AppSettingsRow(title: String(localized: "App-Icon dynamisch"),
                               detail: String(localized: "Gleiche Farbe wie Graph-Farbe."),
                               symbol: "app.badge") {
                    EmptyView()
                }
            }
            .accessibilityIdentifier("match-icon-toggle")

            if !store.matchAppIcon {
                iconGrid
            }

            if iconChangeFailed {
                Text(String(localized: "Der Icon-Wechsel ist auf diesem Gerät gerade nicht möglich."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var materialBinding: Binding<AppearanceMaterial> {
        Binding(
            get: { store.appearancePreferences.material },
            set: { material in
                updateAppearance { $0.material = material }
            })
    }

    private var designStyleBinding: Binding<AppDesignStyle> {
        Binding(
            get: { store.appearancePreferences.designStyle },
            set: { style in
                updateAppearance { $0.designStyle = style }
            })
    }

    private var performanceModeBinding: Binding<Bool> {
        Binding(
            get: { store.appearancePreferences.performanceMode },
            set: { enabled in
                updateAppearance { $0.performanceMode = enabled }
            })
    }

    private var backgroundModeBinding: Binding<AppearanceBackgroundMode> {
        Binding(
            get: { store.appearancePreferences.backgroundMode },
            set: { mode in
                backgroundImageImportToken = UUID()
                updateAppearance {
                    $0.selectBackgroundMode(mode)
                }
                pickedBackgroundItem = nil
            })
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Theme.color(store.appearancePreferences.backgroundColorHex
                            ?? fallbackBackgroundColorHex)
            },
            set: { color in
                updateAppearance { $0.backgroundColorHex = Theme.hex(from: color) }
            })
    }

    private var gradientStartBinding: Binding<Color> {
        Binding(
            get: {
                Theme.color(store.appearancePreferences.gradientStartHex
                            ?? fallbackGradientStartHex)
            },
            set: { color in
                updateAppearance { $0.gradientStartHex = Theme.hex(from: color) }
            })
    }

    private var gradientEndBinding: Binding<Color> {
        Binding(
            get: {
                Theme.color(store.appearancePreferences.gradientEndHex
                            ?? fallbackGradientEndHex)
            },
            set: { color in
                updateAppearance { $0.gradientEndHex = Theme.hex(from: color) }
            })
    }

    private var fallbackBackgroundColorHex: UInt32 {
        colorScheme == .dark ? 0x1C1C1E : 0xF2F2F7
    }

    private var fallbackGradientStartHex: UInt32 {
        colorScheme == .dark ? 0x1C1C1E : 0xF2F2F7
    }

    private var fallbackGradientEndHex: UInt32 {
        colorScheme == .dark ? 0x2C2C2E : 0xE5E5EA
    }

    /// A small set of calm starting points keeps the background editor useful
    /// without turning it into a wall of color controls. The ColorPicker still
    /// accepts any custom color.
    private static let backgroundSwatches: [UInt32] = [
        0xF4F7F2, 0xE7F0FA, 0xF7ECE2, 0xF0EAF7,
        0x202428, 0x202B2A, 0x24263A, 0x2D2520
    ]

    private func updateAppearance(_ body: (inout AppearancePreferences) -> Void) {
        var next = store.appearancePreferences
        body(&next)
        store.appearancePreferences = next
    }

    private var backgroundControl: some View {
        return VStack(alignment: .leading, spacing: currentAppearance.designStyle.rowGap * 2 + 2) {
            Text(String(localized: "Hintergrund"))
                .font(currentAppearance.designStyle.sectionTitleFont)

            backgroundPreview

            backgroundModeSelector

            switch store.appearancePreferences.backgroundMode {
            case .color:
                backgroundColorRow(title: String(localized: "Farbe"),
                                   symbol: "circle.fill",
                                   selection: backgroundColorBinding,
                                   selectedHex: store.appearancePreferences.backgroundColorHex) { hex in
                    updateAppearance { $0.backgroundColorHex = hex }
                }
                .accessibilityIdentifier("appearance-background-color-picker")
            case .gradient:
                backgroundColorRow(title: String(localized: "Oben"),
                                   symbol: "arrow.up",
                                   selection: gradientStartBinding,
                                   selectedHex: store.appearancePreferences.gradientStartHex) { hex in
                    updateAppearance { $0.gradientStartHex = hex }
                }
                    .accessibilityIdentifier("appearance-gradient-start-picker")
                backgroundColorRow(title: String(localized: "Unten"),
                                   symbol: "arrow.down",
                                   selection: gradientEndBinding,
                                   selectedHex: store.appearancePreferences.gradientEndHex) { hex in
                    updateAppearance { $0.gradientEndHex = hex }
                }
                    .accessibilityIdentifier("appearance-gradient-end-picker")
            case .image:
                backgroundImagePicker
            }
        }
    }

    private var backgroundModeSelector: some View {
        Picker(selection: backgroundModeBinding) {
            ForEach(AppearanceBackgroundMode.allCases, id: \.self) { mode in
                Label(mode.displayName, systemImage: backgroundSymbol(for: mode))
                    .tag(mode)
            }
        } label: {
            Text(String(localized: "Hintergrund"))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minHeight: currentAppearance.designStyle.settingsRowHeight)
        .accessibilityLabel(String(localized: "Hintergrund"))
        .accessibilityIdentifier("appearance-background-mode-picker")
    }

    private func backgroundSymbol(for mode: AppearanceBackgroundMode) -> String {
        switch mode {
        case .color: "circle.fill"
        case .gradient: "circle.lefthalf.filled"
        case .image: "photo"
        }
    }

    private func backgroundColorRow(title: String,
                                    symbol: String,
                                    selection: Binding<Color>,
                                    selectedHex: UInt32?,
                                    apply: @escaping (UInt32) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            AppSettingsRow(title: title, symbol: symbol) {
                ColorPicker(String(localized: "Eigene Farbe"),
                            selection: selection,
                            supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityIdentifier("appearance-custom-color-\(title)")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Metrics.hit), spacing: 4)],
                      spacing: 4) {
                ForEach(Self.backgroundSwatches, id: \.self) { hex in
                    Button {
                        apply(hex)
                    } label: {
                        Circle()
                            .fill(Theme.color(hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle()
                                    .stroke(hex == selectedHex
                                            ? Color.primary.opacity(0.85)
                                            : Color.primary.opacity(0.16),
                                            lineWidth: hex == selectedHex ? 2 : 0.75)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                    .contentShape(Circle())
                    .accessibilityLabel(String(localized: "Farbton"))
                    .accessibilityValue(hex == selectedHex
                                       ? String(localized: "Ausgewählt")
                                       : "")
                }
            }
        }
        .frame(minHeight: currentAppearance.designStyle.settingsRowHeight, alignment: .leading)
    }

    @ViewBuilder
    private var backgroundPreview: some View {
        ZStack(alignment: .bottomLeading) {
            AppearanceBackground(preferences: currentAppearance)
            HStack(spacing: 6) {
                Text(verbatim: "hAiity")
                    .font(.headline.weight(.bold))
                Text(String(localized: "dein Raum"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 82)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.panel, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var backgroundImagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Metrics.gap) {
                PhotosPicker(selection: $pickedBackgroundItem,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Label(String(localized: "Bild auswählen"),
                          systemImage: "photo.on.rectangle.angled")
                        .font(currentAppearance.designStyle.rowTitleFont)
                        .frame(maxWidth: .infinity,
                               minHeight: currentAppearance.designStyle.settingsRowHeight,
                               alignment: .leading)
                }
                // Bordered buttons inside an inset-grouped List row can lose
                // their hit target on iOS 27. Keep the native picker control,
                // but make the whole row the explicit, plain hit surface.
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .tint(Theme.accentText(palettes.style))
                .accessibilityIdentifier("appearance-background-picker")

                if hasPersistedBackgroundImage {
                    Button(role: .destructive) {
                        backgroundImageImportToken = UUID()
                        pickedBackgroundItem = nil
                        store.removeBackgroundImage()
                        backgroundImageError = false
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .help(String(localized: "Hintergrundbild entfernen"))
                    .accessibilityLabel(String(localized: "Hintergrundbild entfernen"))
                    .accessibilityIdentifier("appearance-background-remove")
                }
            }
            .frame(minHeight: currentAppearance.designStyle.settingsRowHeight, alignment: .center)
            .onChange(of: pickedBackgroundItem) { _, item in
                guard let item else { return }
                backgroundImageError = false
                let token = UUID()
                backgroundImageImportToken = token
                Task {
                    do {
                        let data = try await item.loadTransferable(type: Data.self)
                        await MainActor.run {
                            guard token == backgroundImageImportToken else { return }
                            guard let data else {
                                backgroundImageError = true
                                pickedBackgroundItem = nil
                                return
                            }
                            importBackgroundImage(data)
                            pickedBackgroundItem = nil
                        }
                    } catch {
                        await MainActor.run {
                            guard token == backgroundImageImportToken else { return }
                            backgroundImageError = true
                            pickedBackgroundItem = nil
                        }
                    }
                }
            }

            if currentAppearance.imagePayload != nil {
                AppearanceCachedImage(data: currentAppearance.imagePayload) {
                    Color(.secondarySystemGroupedBackground)
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showingBackgroundCrop = true }
                    .accessibilityLabel(String(localized: "Ausgewähltes Hintergrundbild"))
                    .accessibilityHint(String(localized: "Tippen, um den Bildausschnitt anzupassen"))
            }
            if backgroundImageError {
                Text(String(localized: "Das Bild konnte nicht übernommen werden."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $showingBackgroundCrop) {
            BackgroundCropSheet(preferences: store.appearancePreferences) { x, y, zoom in
                updateAppearance {
                    $0.backgroundImageFocusX = x
                    $0.backgroundImageFocusY = y
                    $0.backgroundImageZoom = zoom
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func importBackgroundImage(_ data: Data) {
        let token = UUID()
        backgroundImageImportToken = token
        Task {
            let normalized = await Task.detached(priority: .userInitiated) {
                AppearanceImage.normalizedData(data)
            }.value
            await MainActor.run {
                guard token == backgroundImageImportToken else { return }
                guard let normalized else {
                    backgroundImageError = true
                    return
                }
                var next = store.appearancePreferences
                guard next.setBackgroundImage(normalized) else {
                    backgroundImageError = true
                    return
                }
                store.appearancePreferences = next
                backgroundImageError = false
                showingBackgroundCrop = true
            }
        }
    }

    // MARK: – App-Icon-Auswahl
    //
    // Der Schalter darüber ist der AUTOMATIK-Modus (Icon folgt der
    // Graph-Farbe). Das Raster ist der manuelle: ein Tipp setzt das Icon fest
    // und schaltet die Automatik aus. Vorher gab es NUR den Schalter — und
    // wer die grüne Standardfarbe benutzt, sah beim Umlegen exakt nichts
    // (Grün ist das Primär-Icon), was sich als „deaktiviert" las.

    private var iconGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                ForEach(GraphPalette.allCases) { palette in
                    iconCell(named: AppIcons.name(for: palette),
                             style: palette.style,
                             label: palette.displayName,
                             identifier: "app-icon-\(palette.rawValue)")
                }
                ForEach(AppIcons.hues) { hue in
                    iconCell(named: hue.name,
                             style: hue.style,
                             label: String(localized: "Farbton \(hue.degrees)°"),
                             identifier: "app-icon-h\(hue.degrees)")
                }
            }
            freeIconColorRow
        }
        .padding(.vertical, 4)
        .onAppear {
            currentIconName = AppIcons.validManualName(store.manualAppIconName)
                ?? UIApplication.shared.alternateIconName
        }
    }

    /// Welches Icon gerade auf dem Homescreen liegt — mit Automatik das aus
    /// der Graph-Farbe hergeleitete, sonst das zuletzt gesetzte.
    private var selectedIconName: String? {
        store.matchAppIcon
            ? AppIcons.iconName(for: palettes.global, customs: palettes.customs)
            : currentIconName
    }

    private func iconCell(named name: String?, style: PaletteStyle,
                          label: String, identifier: String) -> some View {
        let selected = selectedIconName == name
        return Button {
            chooseIcon(named: name)
        } label: {
            VStack(spacing: 4) {
                // Gezeichnet statt aus dem Katalog geladen: die
                // Alternate-Iconsets liegen in Assets.car, aber
                // `UIImage(named:)` findet .appiconset-Bilder nicht
                // zuverlässig (im Simulator gar nicht). Die Miniatur baut
                // das Icon-Motiv nach — dunkle Kachel, Raster in der Rampe.
                iconThumbnail(style: style)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous)
                            .strokeBorder(selected ? Theme.accentFill(palettes.style)
                                                   : Color.secondary.opacity(0.25),
                                          lineWidth: selected ? 2.5 : 1))
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(selected
                                     ? AnyShapeStyle(Theme.accentText(palettes.style))
                                     : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// Freie Farbe: das Farbrad wählt, die Miniatur daneben zeigt EHRLICH
    /// das eingebaute Icon, das daraus wird (iOS kann nur mitgelieferte
    /// Icons setzen), und „Anwenden" setzt genau dieses.
    private var freeIconColorRow: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            HStack(spacing: 12) {
                ColorPicker(selection: $freeIconColor, supportsOpacity: false) {
                    Label(String(localized: "Eigene Icon-Farbe"), systemImage: "paintpalette")
                        .font(currentAppearance.designStyle.rowTitleFont)
                }
                .accessibilityIdentifier("icon-color-picker")
                .frame(maxWidth: .infinity, alignment: .leading)
                iconThumbnail(style: AppIcons.style(forIconName: snappedFreeIconName))
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
                    .accessibilityHidden(true)
            }
            freeIconColorAction
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: currentAppearance.designStyle.settingsRowHeight, alignment: .leading)
    }

    /// Gegated ist nur das SETZEN. Farbrad und ehrliche Vorschau bleiben —
    /// wer sehen will, welches der 18 Icons aus seiner Farbe würde, soll das
    /// sehen dürfen; die 18 Kacheln darüber sind ohnehin frei.
    @ViewBuilder
    private var freeIconColorAction: some View {
        if unlocked {
            Button(String(localized: "Anwenden")) {
                chooseIcon(named: snappedFreeIconName)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Theme.accentFill(palettes.style))
            .accessibilityIdentifier("icon-color-apply")
        } else {
            Button {
                paywall = .icon
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "lock")
                    Text(verbatim: "Pro")
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Nur mit hAiity Pro"))
            .accessibilityIdentifier("icon-color-pro")
        }
    }

    var snappedFreeIconName: String? {
        AppIcons.iconName(forBase: Theme.hex(from: freeIconColor))
    }

    /// Das Icon-Motiv als Miniatur: dunkle Kachel, darauf ein 2×2-Raster in
    /// den Stufen der Familie — dieselbe Rampe wie im Jahresraster.
    private func iconThumbnail(style: PaletteStyle) -> some View {
        ZStack {
            Color(red: 0.09, green: 0.11, blue: 0.10)
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { col in
                            RoundedRectangle(cornerRadius: CornerRadius.pixel, style: .continuous)
                                .fill(Theme.level([2, 4, 3, 1][row * 2 + col],
                                                  dark: true, palette: style))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }

    /// Manuelle Wahl: Automatik aus, Icon setzen, Ergebnis zurückmelden.
    func chooseIcon(named name: String?) {
        store.manualAppIconName = name
        store.matchAppIcon = false
        Task {
            let ok = await AppIcons.set(name)
            await MainActor.run {
                iconChangeFailed = !ok
                // Nicht zurücklesen: `alternateIconName` hinkt der Animation
                // des System-Dialogs hinterher, und die Markierung stünde
                // einen Moment auf dem falschen Icon.
                currentIconName = ok ? name
                                     : UIApplication.shared.alternateIconName
            }
        }
    }

    // MARK: – Graph-Farbe
    //
    // Die Auswahl IST das Raster: jede Zeile zeigt ihre fünf Stufen als
    // dieselben Quadrate, die später im Jahresraster stehen (`GridCell`),
    // nicht als Farbpunkte. Eine eigene Farbe steht gleichberechtigt zwischen
    // den eingebauten — sie kann nur zusätzlich umbenannt, umgefärbt und
    // gelöscht werden.

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Graph-Farbe"))
                .font(currentAppearance.designStyle.sectionTitleFont)
                .foregroundStyle(.secondary)
                .padding(.bottom, currentAppearance.designStyle.rowGap * 2)

            ForEach(GraphPalette.allCases) { palette in
                PaletteRow(style: palette.style,
                           title: palette.displayName,
                           selected: store.palette == .builtin(palette)) {
                    select(.builtin(palette))
                }
                .accessibilityIdentifier("palette-row-\(palette.rawValue)")
                .padding(.vertical, currentAppearance.designStyle.rowGap * 2)
            }
            ForEach(unlocked ? store.customPalettes : []) { custom in
                PaletteRow(style: custom.style,
                           title: custom.displayName,
                           selected: store.palette == .custom(custom.id)) {
                    selectCustomPalette(custom.id)
                }
                .accessibilityIdentifier("palette-row-custom-\(custom.id.uuidString)")
                .padding(.vertical, currentAppearance.designStyle.rowGap * 2)
                .swipeActions(edge: .trailing) {
                    // Rot EXPLIZIT: der App-Tint (die eigene Farbe!) würde die
                    // zerstörende Rolle sonst übermalen — eine Löschen-Taste in
                    // Petrol sieht aus wie eine harmlose Aktion.
                    Button(role: .destructive) { requestDelete(custom) } label: {
                        Label(String(localized: "Löschen"), systemImage: "trash")
                    }
                    .tint(.red)
                    Button { editingPalette = custom } label: {
                        Label(String(localized: "Bearbeiten"), systemImage: "paintpalette")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        renameText = custom.name
                        renamingPalette = custom
                    } label: {
                        Label(String(localized: "Umbenennen"), systemImage: "pencil")
                    }
                    Button { editingPalette = custom } label: {
                        Label(String(localized: "Bearbeiten"), systemImage: "paintpalette")
                    }
                    Button(role: .destructive) { requestDelete(custom) } label: {
                        Label(String(localized: "Löschen"), systemImage: "trash")
                    }
                }
            }
            Button {
                requestCustomPalette()
            } label: {
                AppSettingsRow(title: String(localized: "Eigene Farbe …"),
                               symbol: "plus.circle") {
                    if !unlocked { proLock }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .padding(.vertical, currentAppearance.designStyle.rowGap * 2)
            .accessibilityIdentifier("palette-add-custom")
        }
    }

    /// Frage im Löschen-Dialog. Sie NENNT, was betroffen ist — eine Farbe,
    /// die gerade nichts einfärbt, wird ohne Rückfrage gelöscht.
    var deleteQuestion: String {
        guard let palette = deletingPalette else { return "" }
        return String(localized: "„\(palette.displayName)“ wird noch benutzt. Löschen?")
    }

    /// Eigene Farben ANLEGEN ist Pro — der Bestand nicht: vorhandene eigene
    /// Farben bleiben wählbar, umbenennbar, bearbeitbar und löschbar. Bezahlt
    /// wird das Neue, nie das Vorhandene.
    private func requestCustomPalette() {
        guard ProGate.mayUseProFeature(unlocked: unlocked) else {
            paywall = .palette
            return
        }
        creatingPalette = true
    }

    private func selectCustomPalette(_ id: UUID) {
        guard ProGate.mayUseProFeature(unlocked: unlocked) else {
            paywall = .palette
            return
        }
        select(.custom(id))
    }

    private func requestDelete(_ palette: CustomPalette) {
        if store.isCustomPaletteInUse(palette.id) {
            deletingPalette = palette
        } else {
            store.removeCustomPalette(palette.id)
        }
    }

    func commitRename() {
        guard var palette = renamingPalette else { return }
        palette.name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateCustomPalette(palette)
        renamingPalette = nil
    }

    /// Global gibt es kein „Wie App": eine Farbe ist immer gesetzt.
    private func select(_ ref: PaletteRef) {
        guard ref != store.palette else { return }
        store.palette = ref
    }

    private var appearanceBinding: Binding<AppearanceSetting> {
        Binding(get: { store.appearance }, set: { store.appearance = $0 })
    }

    private var matchIconBinding: Binding<Bool> {
        Binding(
            get: { store.matchAppIcon },
            set: { on in
                store.matchAppIcon = on
                applyIconPreference()
            })
    }

    func applyIconPreference() {
        let wanted = store.matchAppIcon
            ? AppIcons.iconName(for: palettes.global, customs: palettes.customs)
            : AppIcons.validManualName(store.manualAppIconName)
        Task {
            let ok = await AppIcons.set(wanted)
            await MainActor.run {
                currentIconName = ok ? wanted : UIApplication.shared.alternateIconName
            }
        }
    }
}
