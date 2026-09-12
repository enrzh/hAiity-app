import SwiftUI
import UIKit
import ImageIO

/// Erscheinungsbild der App. `system` = dem Gerät folgen (kein Override).
enum AppearanceSetting: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    static let `default` = AppearanceSetting.system

    /// Was `.preferredColorScheme` bekommt — nil heißt "nicht erzwingen".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Hell")
        case .dark: return String(localized: "Dunkel")
        }
    }
}

enum AppearanceMaterial: String, CaseIterable, Codable, Sendable {
    case solid
    case milky
    case liquid
    case adaptive

    var displayName: String {
        switch self {
        case .solid: return String(localized: "Solid")
        case .milky: return String(localized: "Milchglas")
        case .liquid: return String(localized: "Liquid Glass")
        case .adaptive: return String(localized: "Auto")
        }
    }

    /// Ein Satz unter der Vorschau-Auswahl, der sagt, was die gewählte
    /// Oberfläche tatsächlich tut — „Auto" ohne Erklärung wäre Rätselraten.
    var hint: String {
        switch self {
        case .solid:
            return String(localized: "Deckende Flächen in einer ruhigen Farbe.")
        case .milky:
            return String(localized: "Milchig getönte Flächen, die den Hintergrund erahnen.")
        case .liquid:
            return String(localized: "Echtes Liquid Glass mit Tiefenwirkung (ab iOS 26, sonst Milchglas).")
        case .adaptive:
            return String(localized: "Passt Fläche und Kontrast automatisch an deinen Hintergrund an.")
        }
    }
}

enum AppearanceBackgroundMode: String, CaseIterable, Codable, Sendable {
    case color
    case gradient
    case image

    var displayName: String {
        switch self {
        case .color: return String(localized: "Farbe")
        case .gradient: return String(localized: "Verlauf")
        case .image: return String(localized: "Bild")
        }
    }
}

/// Persisted appearance choices shared by the app and iCloud payload. Image
/// bytes are intentionally bounded because they travel with the full habit
/// asset even though CloudKit stores that asset outside the record fields.
struct AppearancePreferences: Codable, Equatable, Sendable {
    static let maxImageBytes = 600 * 1024
    static let `default` = AppearancePreferences(material: .solid)

    var material: AppearanceMaterial
    var backgroundMode: AppearanceBackgroundMode
    var backgroundColorHex: UInt32?
    var gradientStartHex: UInt32?
    var gradientEndHex: UInt32?
    var backgroundImageData: Data?
    /// Disables expensive glass effects while keeping the selected background
    /// and colors intact.
    var performanceMode: Bool
    /// Last destructive/new-image background mutation. It is a small iCloud
    /// tombstone: an older payload must not resurrect a removed image.
    var backgroundResetAt: TimeInterval?

    init(material: AppearanceMaterial = .solid,
         backgroundImageData: Data? = nil,
         backgroundMode: AppearanceBackgroundMode? = nil,
         backgroundColorHex: UInt32? = nil,
         gradientStartHex: UInt32? = nil,
         gradientEndHex: UInt32? = nil,
         backgroundResetAt: TimeInterval? = nil,
         performanceMode: Bool = false) {
        let boundedImage = backgroundImageData.flatMap(Self.usableImageData)
        let requestedMode = backgroundMode ?? (boundedImage == nil ? .color : .image)
        self.material = material
        // An explicitly selected Image mode is also valid before a replacement
        // photo is chosen. Keeping that state visible is what makes the native
        // picker recoverable after a deleted or invalid iCloud payload.
        self.backgroundMode = requestedMode
        self.backgroundColorHex = backgroundColorHex
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        // A photo only belongs to Image mode. Keeping it in Color/Gradient
        // makes stale iCloud payloads look like a locked editor state.
        self.backgroundImageData = requestedMode == .image ? boundedImage : nil
        self.backgroundResetAt = backgroundResetAt
        self.performanceMode = performanceMode
    }

    /// The JSON payload is also written by older builds and by iCloud merges.
    /// A byte-size check alone accepts truncated or non-image data, leaving the
    /// UI stuck in `.image` after the photo itself can no longer be decoded.
    func normalizedForStorage() -> AppearancePreferences {
        var normalized = self
        if backgroundMode != .image {
            normalized.backgroundImageData = nil
        } else if let image = backgroundImageData {
            if let usable = Self.usableImageData(image) {
                normalized.backgroundImageData = usable
            } else {
                normalized.backgroundImageData = nil
            }
        }
        return normalized
    }

    private static func usableImageData(_ data: Data) -> Data? {
        guard data.count <= maxImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 32,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceShouldCache: false
                  ] as CFDictionary) != nil else {
            return nil
        }
        return data
    }

    mutating func selectBackgroundMode(_ mode: AppearanceBackgroundMode) {
        backgroundMode = mode
        if mode == .image {
            // Drop corrupt bytes, but keep Image selected so the picker stays
            // visible and the user can repair the background in one tap.
            backgroundImageData = backgroundImageData.flatMap(Self.usableImageData)
        } else {
            backgroundImageData = nil
        }
    }

    /// Installs a validated image and selects image mode in one mutation. The
    /// importer must not publish the transient state `.image` without bytes:
    /// the store normalizer correctly repairs that state back to `.color`.
    @discardableResult
    mutating func setBackgroundImage(_ data: Data) -> Bool {
        guard let usable = Self.usableImageData(data) else { return false }
        backgroundImageData = usable
        backgroundMode = .image
        backgroundResetAt = Date().timeIntervalSince1970
        return true
    }

    /// Explicitly removes the stored photo. Selecting another mode remains
    /// reversible and must not call this operation.
    mutating func removeBackgroundImage() {
        backgroundImageData = nil
        backgroundMode = .color
        backgroundResetAt = Date().timeIntervalSince1970
    }

    mutating func resetBackground() {
        backgroundMode = .color
        backgroundColorHex = nil
        gradientStartHex = nil
        gradientEndHex = nil
        backgroundImageData = nil
        backgroundResetAt = Date().timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey {
        case material, backgroundMode, backgroundColorHex, gradientStartHex,
             gradientEndHex, backgroundImageData, backgroundResetAt,
             performanceMode, adaptive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let image = try c.decodeIfPresent(Data.self, forKey: .backgroundImageData)
        let rawMaterial = try c.decodeIfPresent(String.self, forKey: .material)
        let legacyMaterial = rawMaterial.flatMap(AppearanceMaterial.init(rawValue:)) ?? .solid
        let isAdaptive = try c.decodeIfPresent(Bool.self, forKey: .adaptive) ?? false
        self.init(
            material: isAdaptive ? .adaptive : legacyMaterial,
            backgroundImageData: image,
            backgroundMode: try c.decodeIfPresent(AppearanceBackgroundMode.self,
                                                    forKey: .backgroundMode)
                ?? (image == nil ? .color : .image),
            backgroundColorHex: try c.decodeIfPresent(UInt32.self, forKey: .backgroundColorHex),
            gradientStartHex: try c.decodeIfPresent(UInt32.self, forKey: .gradientStartHex),
            gradientEndHex: try c.decodeIfPresent(UInt32.self, forKey: .gradientEndHex),
            backgroundResetAt: try c.decodeIfPresent(TimeInterval.self,
                                                      forKey: .backgroundResetAt),
            performanceMode: try c.decodeIfPresent(Bool.self,
                                                   forKey: .performanceMode) ?? false)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if material == .adaptive {
            // Older builds understand this as Solid and ignore the additive
            // marker instead of failing the complete iCloud payload.
            try c.encode(AppearanceMaterial.solid.rawValue, forKey: .material)
            try c.encode(true, forKey: .adaptive)
        } else {
            try c.encode(material.rawValue, forKey: .material)
        }
        try c.encode(backgroundMode, forKey: .backgroundMode)
        try c.encodeIfPresent(backgroundColorHex, forKey: .backgroundColorHex)
        try c.encodeIfPresent(gradientStartHex, forKey: .gradientStartHex)
        try c.encodeIfPresent(gradientEndHex, forKey: .gradientEndHex)
        try c.encodeIfPresent(backgroundImageData, forKey: .backgroundImageData)
        try c.encodeIfPresent(backgroundResetAt, forKey: .backgroundResetAt)
        try c.encode(performanceMode, forKey: .performanceMode)
    }

    var backgroundImage: UIImage? {
        guard let backgroundImageData else { return nil }
        return AppearanceImageCache.image(for: backgroundImageData)
    }

    /// Raw persisted bytes for controls that must remain usable even when the
    /// image is corrupt or has not been prepared for rendering yet.
    var imagePayload: Data? { backgroundImageData }

    /// SwiftUI task identity must stay small. New payloads use the existing
    /// iCloud mutation marker; legacy payloads without it retain data-change
    /// invalidation through a compact hash.
    var backgroundImageIdentity: AnyHashable? {
        guard backgroundMode == .image, let backgroundImageData else { return nil }
        if let backgroundResetAt {
            return AnyHashable("reset:\(backgroundResetAt)")
        }
        return AnyHashable("legacy:\(AppearanceImageCache.identity(for: backgroundImageData))")
    }
}

/// Decoded background images are reused across the many SwiftUI surfaces that
/// can be mounted during launch. The persisted JPEG remains the source of
/// truth; this cache is only an in-process rendering optimization.
enum AppearanceImageCache {
#if DEBUG
    private static let launchRasterProbeLock = NSLock()
    private static var _launchRasterProbe: ((CGSize, CGFloat) -> Void)?

    static func setLaunchRasterProbe(_ probe: ((CGSize, CGFloat) -> Void)?) {
        launchRasterProbeLock.lock()
        _launchRasterProbe = probe
        launchRasterProbeLock.unlock()
    }
#endif

    private final class Entry: @unchecked Sendable {
        let image: UIImage
        let averageHex: UInt32?

        init(image: UIImage, averageHex: UInt32?) {
            self.image = image
            self.averageHex = averageHex
        }
    }

    private final class InFlight: @unchecked Sendable {
        let task: Task<Entry?, Never>
        var waiters: Int

        init(task: Task<Entry?, Never>, waiters: Int) {
            self.task = task
            self.waiters = waiters
        }
    }

    private final class CacheKey: NSObject {
        private let namespace: UInt8
        private let value: AnyHashable

        private init(namespace: UInt8, value: AnyHashable) {
            self.namespace = namespace
            self.value = value
        }

        static func image(_ data: Data) -> CacheKey {
            CacheKey(namespace: 1, value: AnyHashable(data))
        }

        static func launch(_ key: String) -> CacheKey {
            CacheKey(namespace: 2, value: AnyHashable(key))
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(namespace)
            hasher.combine(value)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return namespace == other.namespace && value == other.value
        }
    }

    private final class Store: @unchecked Sendable {
        let cache: NSCache<CacheKey, Entry> = {
            let cache = NSCache<CacheKey, Entry>()
            cache.countLimit = 4
            cache.totalCostLimit = 32 * 1024 * 1024
            return cache
        }()
    }

    private actor InFlightStore {
        private var inFlight: [Data: InFlight] = [:]

        func acquire(for data: Data,
                     start: @escaping @Sendable () -> Entry?) -> InFlight {
            if let existing = inFlight[data] {
                existing.waiters += 1
                return existing
            }

            let next = InFlight(task: Task(priority: .userInitiated) {
                guard !Task.isCancelled else { return nil }
                let prepared = start()
                guard !Task.isCancelled else { return nil }
                return prepared
            }, waiters: 1)
            inFlight[data] = next
            return next
        }

        func release(_ task: InFlight,
                     for data: Data,
                     cancelIfOrphaned: Bool) {
            guard let current = inFlight[data], current === task else { return }
            current.waiters = max(0, current.waiters - 1)
            if current.waiters == 0 {
                if cancelIfOrphaned {
                    current.task.cancel()
                }
                inFlight[data] = nil
            }
        }
    }

    private static let store = Store()
    private final class LaunchInFlight: @unchecked Sendable {
        let task: Task<CGImage?, Never>
        var waiters: Int

        init(task: Task<CGImage?, Never>, waiters: Int) {
            self.task = task
            self.waiters = waiters
        }
    }

    private actor LaunchInFlightStore {
        private var inFlight: [String: LaunchInFlight] = [:]

        func acquire(key: String, start: @escaping @Sendable () -> CGImage?) -> LaunchInFlight {
            if let existing = inFlight[key] {
                existing.waiters += 1
                return existing
            }
            let next = LaunchInFlight(task: Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return nil }
                return start()
            }, waiters: 1)
            inFlight[key] = next
            return next
        }

        func release(_ task: LaunchInFlight, key: String, cancelIfOrphaned: Bool) {
            guard let current = inFlight[key], current === task else { return }
            current.waiters = max(0, current.waiters - 1)
            if current.waiters == 0 {
                if cancelIfOrphaned { current.task.cancel() }
                Task { [weak self] in
                    _ = await current.task.value
                    await self?.finish(current, key: key)
                }
            }
        }

        func finish(_ task: LaunchInFlight, key: String) {
            guard let current = inFlight[key], current === task else { return }
            guard current.waiters == 0 else { return }
            inFlight[key] = nil
        }
    }

    private static let inFlightStore = InFlightStore()
    private static let launchInFlightStore = LaunchInFlightStore()

    static func image(for data: Data) -> UIImage? {
        entry(for: data)?.image
    }

    static func identity(for data: Data) -> Int {
        var digest: UInt64 = 1469598103934665603
        digest ^= UInt64(data.count)
        digest &*= 1099511628211
        for byte in data.prefix(64) {
            digest ^= UInt64(byte)
            digest &*= 1099511628211
        }
        for byte in data.suffix(64) {
            digest ^= UInt64(byte)
            digest &*= 1099511628211
        }
        return Int(truncatingIfNeeded: digest)
    }

    /// Read only an already prepared image. This is the hot path used by the
    /// full-screen background; it must never start JPEG decoding during a
    /// SwiftUI body evaluation.
    static func cachedImage(for data: Data) -> UIImage? {
        store.cache.object(forKey: CacheKey.image(data))?.image
    }

    static func averageHex(for data: Data) -> UInt32? {
        entry(for: data)?.averageHex
    }

    static func cachedAverageHex(for data: Data) -> UInt32? {
        store.cache.object(forKey: CacheKey.image(data))?.averageHex
    }

    /// Rasterize the bundled launch graph once for the measured window. Keep
    /// this asset in the same image-cache boundary as user backgrounds so
    /// startup never grows a second ad-hoc image cache.
    private nonisolated static func rasterizeLaunchTiles(size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0, scale > 0 else { return nil }

#if DEBUG
        launchRasterProbeLock.lock()
        let probe = _launchRasterProbe
        launchRasterProbeLock.unlock()
        probe?(size, scale)
#endif

        guard let source = UIImage(named: "LaunchTiles") else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        return image
    }

    static func launchTilesImageTask(size: CGSize, scale: CGFloat) async -> CGImage? {
        let key = "launch-tiles-\(Int((size.width * scale).rounded()))x\(Int((size.height * scale).rounded()))"
        let cacheKey = CacheKey.launch(key)
        if let cached = store.cache.object(forKey: cacheKey) {
            return cached.image.cgImage
        }
        let request = await launchInFlightStore.acquire(key: key) {
            guard let image = rasterizeLaunchTiles(size: size, scale: scale) else { return nil }
            store.cache.setObject(Entry(image: image, averageHex: nil), forKey: cacheKey)
            return image.cgImage
        }
        let result = await withTaskCancellationHandler {
            await request.task.value
        } onCancel: {
            Task { await launchInFlightStore.release(request, key: key, cancelIfOrphaned: true) }
        }
        await launchInFlightStore.release(request, key: key, cancelIfOrphaned: false)
        return Task.isCancelled ? nil : result
    }

    /// Decode the selected background while the launch animation is already
    /// on screen. `UIImage(data:)` is lazy, so merely caching that wrapper
    /// still leaves the first SwiftUI draw responsible for the JPEG decode.
    static func prewarm(data: Data?) async {
        guard let data else { return }
        await prepareEntry(for: data)
    }

    static func prewarmTask(data: Data?) -> Task<Void, Never>? {
        guard let data else { return nil }
        return Task {
            await prepareEntry(for: data)
        }
    }

    private static func entry(for data: Data) -> Entry? {
        if let cached = store.cache.object(forKey: CacheKey.image(data)) {
            return cached
        }

        guard let entry = buildEntry(for: data) else { return nil }
        storeEntry(entry, for: data)
        return entry
    }

    private static func prepareEntry(for data: Data) async {
        if store.cache.object(forKey: CacheKey.image(data)) != nil { return }

        let inFlight = await inFlightStore.acquire(for: data) {
            buildEntry(for: data)
        }
        let entry = await withTaskCancellationHandler {
            await inFlight.task.value
        } onCancel: {
            Task {
                await inFlightStore.release(inFlight, for: data, cancelIfOrphaned: true)
            }
        }
        guard !Task.isCancelled else { return }
        await inFlightStore.release(inFlight, for: data, cancelIfOrphaned: false)
        guard let entry,
              store.cache.object(forKey: CacheKey.image(data)) == nil else { return }
        storeEntry(entry, for: data)
    }

    private static func buildEntry(for data: Data) -> Entry? {
        guard let image = decodedImage(from: data) else { return nil }
        return Entry(image: image, averageHex: averageHex(image))
    }

    private static func storeEntry(_ entry: Entry, for data: Data) {
        let cost = entry.image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
        store.cache.setObject(entry, forKey: CacheKey.image(data), cost: cost)
    }

    private static func decodedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source,
                                                                0,
                                                                options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func averageHex(_ image: UIImage) -> UInt32? {
        guard let image = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let base = bytes.baseAddress,
                  let context = CGContext(data: base,
                                          width: 1,
                                          height: 1,
                                          bitsPerComponent: 8,
                                          bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (UInt32(pixel[0]) << 16) | (UInt32(pixel[1]) << 8) | UInt32(pixel[2])
    }
}

/// Renders a persisted background image only after the shared cache has
/// prepared it. Settings pages can mount this view repeatedly while a list is
/// scrolling; none of those body evaluations should decode JPEG bytes.
struct AppearanceCachedImage<Placeholder: View>: View {
    let data: Data?
    private let imageIdentity: Int?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(data: Data?,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.data = data
        imageIdentity = data.map(AppearanceImageCache.identity)
        self.placeholder = placeholder
        _image = State(initialValue: data.flatMap(AppearanceImageCache.cachedImage))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        // A rendered preview is decoration. Keeping it out of the hit-test
        // tree prevents a cached image from swallowing the controls below it.
        .allowsHitTesting(false)
        .task(id: imageIdentity) {
            image = nil
            guard let data else { return }
            if let cached = AppearanceImageCache.cachedImage(for: data) {
                image = cached
                return
            }
            await AppearanceImageCache.prewarm(data: data)
            guard !Task.isCancelled else { return }
            image = AppearanceImageCache.cachedImage(for: data)
        }
    }
}

enum AppearanceImage {
    /// Downsample and compress a picked image before it enters `HabitData`.
    /// The final size check is repeated by `AppearancePreferences`.
    static func normalizedData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let sourceDimension = max(CGFloat(cgImage.width), CGFloat(cgImage.height))
        let dimensions: [CGFloat] = [1600, 1280, 1024, 840, 720]
        let qualities: [CGFloat] = [0.78, 0.64, 0.52, 0.42, 0.32]

        for maxDimension in dimensions {
            let scale = min(1, maxDimension / sourceDimension)
            let size = CGSize(width: max(1, floor(CGFloat(cgImage.width) * scale)),
                              height: max(1, floor(CGFloat(cgImage.height) * scale)))
            let format = UIGraphicsImageRendererFormat()
            // `size` is expressed in pixels for the persisted JPEG, not in
            // points. Without this, a Retina device silently triples the
            // output dimensions and makes otherwise valid photos too large.
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: size, format: format)

            for quality in qualities {
                let compressed = renderer.jpegData(withCompressionQuality: quality) { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                if compressed.count <= AppearancePreferences.maxImageBytes {
                    return compressed
                }
            }
        }
        return nil
    }
}

/// Farb-Quelle für App und Widget.
///
/// Alles hier nimmt eine `PaletteStyle` — die AUFGELÖSTE Farbtafel. Ob sie aus
/// einer der sechs eingebauten Familien kommt oder aus einer eigenen Farbe des
/// Nutzers gerechnet wurde, weiß ab hier niemand mehr; das entscheidet
/// `PaletteStyle.resolve` genau einmal.
enum Theme {
    // MARK: – Contribution-Level

    /// Die Farbe einer Rasterzelle. `palette` kommt aus der Umgebung
    /// (`\.palettes`) bzw. beim Widget aus dem Timeline-Eintrag; die
    /// Habit-Übersteuerung wird VORHER über `PaletteStyle.resolve` aufgelöst.
    ///
    /// `Habit.Answer.declinedLevel` (−1) ist die eine Stufe NEBEN der Rampe:
    /// ein mit Nein beantworteter Tag. Sie steht hier und nicht in jeder
    /// Ansicht einzeln, weil an dieser Funktion ALLES hängt, was Zellen malt
    /// — Liste, Vorschau, Teilen-Karte und jedes Widget erben die Farbe
    /// damit ohne eigenes Zutun. Jeder ANDERE Ausreißer wird weiter geklemmt
    /// (−3 ist keine Verneinung, sondern ein Fehler, und bleibt l0).
    static func level(_ n: Int, dark: Bool, palette: PaletteStyle = .default) -> Color {
        guard n != Habit.Answer.declinedLevel else {
            return color(palette.negative(dark: dark))
        }
        return color(palette.ramp(dark: dark)[max(0, min(4, n))])
    }

    /// Kartenfarbe (`secondarySystemGroupedBackground`) als Hex — die Fläche,
    /// gegen die l0 bestehen muss. Als Konstante, damit die Kontrast-Tests
    /// nicht von einer Trait-Collection abhängen. EINE Quelle, die auch der
    /// Generator benutzt.
    static func cardHex(dark: Bool) -> UInt32 { PaletteGenerator.cardHex(dark: dark) }

    // MARK: – Akzent
    //
    // Drei Rollen, weil EINE Farbstufe nicht überall lesbar ist:
    //   accent      – Markenfarbe für FLÄCHEN ohne Text (Glas-Tint,
    //                 Monatsbalken, Chip-Hintergründe).
    //   accentFill  – gefüllte Pillen MIT weißer Schrift; dunkel genug für
    //                 ≥ 4,5:1 gegen Weiß.
    //   accentText  – Akzent als SCHRIFT/Symbol auf Systemhintergrund;
    //                 hell im Dark Mode, dunkel im Light Mode.

    static func accent(_ palette: PaletteStyle = .default) -> Color {
        color(palette.accentHex)
    }

    static func accentFill(_ palette: PaletteStyle = .default) -> Color {
        let hex = palette.accentFillHex
        return dynamic(light: hex.light, dark: hex.dark)
    }

    static func accentText(_ palette: PaletteStyle = .default) -> Color {
        let hex = palette.accentTextHex
        return dynamic(light: hex.light, dark: hex.dark)
    }

    // Bequemlichkeits-Überladungen für die eingebauten Familien: Aufrufer, die
    // eine feste Palette meinen (Vorschauen, Tests), müssen nicht erst
    // `.style` schreiben. Ohne Standardwert, damit ein Aufruf ohne Argument
    // eindeutig die `PaletteStyle`-Variante trifft.
    static func level(_ n: Int, dark: Bool, palette: GraphPalette) -> Color {
        level(n, dark: dark, palette: palette.style)
    }
    static func accent(_ palette: GraphPalette) -> Color { accent(palette.style) }
    static func accentFill(_ palette: GraphPalette) -> Color { accentFill(palette.style) }
    static func accentText(_ palette: GraphPalette) -> Color { accentText(palette.style) }

    static func color(_ hex: UInt32) -> Color { Color(uiColor(hex)) }

    /// sRGB-Hex aus einer gewählten `Color`. Der ColorPicker liefert je nach
    /// Gerät Display-P3 oder erweiterte Werte; hier wird EINMAL nach sRGB
    /// gerechnet und geklemmt, damit alles dahinter mit 0xRRGGBB arbeitet.
    static func hex(from color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let ui = UIColor(color)
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0x2EA043 }
        func channel(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        return (channel(r) << 16) | (channel(g) << 8) | channel(b)
    }

    /// The background tone is intentionally derived at render time. Storing
    /// derived colors would make a later background change leave the adaptive
    /// surface stale on another device.
    static func adaptiveReferenceHex(preferences: AppearancePreferences,
                                     dark: Bool) -> UInt32 {
        let fallback: UInt32 = dark ? 0x1C1C1E : 0xF2F2F7
        switch preferences.backgroundMode {
        case .color:
            return preferences.backgroundColorHex ?? fallback
        case .gradient:
            let start = preferences.gradientStartHex ?? fallback
            let end: UInt32 = preferences.gradientEndHex
                ?? (dark ? 0x2C2C2E : 0xE5E5EA)
            return midpoint(start, end)
        case .image:
            return preferences.backgroundImageData
                .flatMap(AppearanceImageCache.cachedAverageHex) ?? fallback
        }
    }

    static func adaptiveTintHex(preferences: AppearancePreferences,
                                dark: Bool) -> UInt32 {
        let reference = uiColor(adaptiveReferenceHex(preferences: preferences, dark: dark))
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard reference.getHue(&hue,
                               saturation: &saturation,
                               brightness: &brightness,
                               alpha: &alpha),
              saturation > 0.08 else {
            return dark ? 0x8AB4F8 : 0x216E39
        }

        let tunedSaturation = min(0.72, max(0.42, saturation + 0.12))
        let tunedBrightness = dark ? 0.78 : 0.54
        return hex(from: UIColor(hue: hue,
                                 saturation: tunedSaturation,
                                 brightness: tunedBrightness,
                                 alpha: 1))
    }

    /// Keeps the user's hue and level semantics, but lifts cells away from a
    /// background that would otherwise swallow GitHub's l0 or l4 tiles.
    static func adaptivePalette(_ palette: PaletteStyle,
                                preferences: AppearancePreferences,
                                dark: Bool) -> PaletteStyle {
        guard effectiveMaterial(preferences) == .adaptive else { return palette }
        let background = adaptiveReferenceHex(preferences: preferences, dark: dark)
        return PaletteStyle(
            lightRamp: palette.lightRamp.map { adaptiveTileHex($0, against: background) },
            darkRamp: palette.darkRamp.map { adaptiveTileHex($0, against: background) },
            accentHex: palette.accentHex,
            accentFillLight: palette.accentFillLight,
            accentFillDark: palette.accentFillDark,
            accentTextLight: palette.accentTextLight,
            accentTextDark: palette.accentTextDark,
            negativeLight: adaptiveTileHex(palette.negativeLight, against: background),
            negativeDark: adaptiveTileHex(palette.negativeDark, against: background))
    }

    static func adaptiveTileOutline(preferences: AppearancePreferences,
                                    dark: Bool) -> Color {
        let background = adaptiveReferenceHex(preferences: preferences, dark: dark)
        return relativeLuminance(background) < 0.5
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.14)
    }

    static func adaptiveSurfaceOpacity(preferences: AppearancePreferences,
                                       dark: Bool) -> CGFloat {
        let luminance = relativeLuminance(adaptiveReferenceHex(preferences: preferences,
                                                                dark: dark))
        let target = dark ? 0.18 : 0.82
        return min(0.30, max(0.10, 0.10 + abs(luminance - target) * 0.34))
    }

    static func adaptiveBackgroundScrimOpacity(preferences: AppearancePreferences,
                                               dark: Bool) -> CGFloat {
        let luminance = relativeLuminance(adaptiveReferenceHex(preferences: preferences,
                                                                dark: dark))
        let target = dark ? 0.18 : 0.82
        return min(0.52, max(0.22, 0.22 + abs(luminance - target) * 0.45))
    }

    /// A quiet rim keeps translucent surfaces legible without adding a card
    /// shadow. The same edge is used by app cards and settings rows so a page
    /// does not switch visual language between controls and content.
    static func surfaceOutline(preferences: AppearancePreferences,
                               dark: Bool) -> Color {
        switch effectiveMaterial(preferences) {
        case .solid:
            return dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
        case .milky:
            return Color.white.opacity(dark ? 0.18 : 0.48)
        case .liquid:
            return Color.white.opacity(dark ? 0.22 : 0.58)
        case .adaptive:
            return adaptiveTileOutline(preferences: preferences, dark: dark)
        }
    }

    static func surfaceTintOpacity(preferences: AppearancePreferences,
                                   dark: Bool) -> Double {
        switch effectiveMaterial(preferences) {
        case .solid: return 0
        case .milky: return 0.16
        case .liquid: return dark ? 0.32 : 0.18
        case .adaptive: return adaptiveSurfaceOpacity(preferences: preferences, dark: dark)
        }
    }

    /// One tint source for every app surface. Performance mode deliberately
    /// uses the solid path so no material or glass effect is constructed.
    static func effectiveMaterial(_ preferences: AppearancePreferences) -> AppearanceMaterial {
        preferences.performanceMode ? .solid : preferences.material
    }

    static func surfaceTint(preferences: AppearancePreferences, dark: Bool) -> Color {
        switch effectiveMaterial(preferences) {
        case .adaptive:
            return color(adaptiveTintHex(preferences: preferences, dark: dark))
        case .solid, .milky, .liquid:
            return Color(.systemBackground)
        }
    }

    /// The opaque fallback shared by app cards and settings rows. Keeping
    /// this here prevents the two surface modifiers from drifting apart.
    static func surfaceFill(preferences: AppearancePreferences) -> Color {
        switch effectiveMaterial(preferences) {
        case .solid, .milky, .liquid, .adaptive:
            return Color(.secondarySystemGroupedBackground)
        }
    }

    static func contrastRatio(_ lhs: UInt32, _ rhs: UInt32) -> Double {
        let a = relativeLuminance(lhs)
        let b = relativeLuminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        let l = uiColor(light), d = uiColor(dark)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }

    private static func midpoint(_ lhs: UInt32, _ rhs: UInt32) -> UInt32 {
        func channel(_ value: UInt32, _ shift: UInt32) -> UInt32 {
            (value >> shift) & 0xFF
        }
        func average(_ a: UInt32, _ b: UInt32) -> UInt32 { (a + b + 1) / 2 }
        return (average(channel(lhs, 16), channel(rhs, 16)) << 16)
            | (average(channel(lhs, 8), channel(rhs, 8)) << 8)
            | average(channel(lhs, 0), channel(rhs, 0))
    }

    private static func adaptiveTileHex(_ value: UInt32, against background: UInt32) -> UInt32 {
        let minimum = 1.15
        guard contrastRatio(value, background) < minimum else { return value }

        let target: UInt32 = relativeLuminance(background) < 0.5 ? 0xFFFFFF : 0x000000
        var candidate = value
        for step in 1...8 {
            let amount = Double(step) / 8 * 0.72
            candidate = mix(value, target, amount: amount)
            if contrastRatio(candidate, background) >= minimum { return candidate }
        }
        return candidate
    }

    private static func mix(_ lhs: UInt32, _ rhs: UInt32, amount: Double) -> UInt32 {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            Double((value >> shift) & 0xFF)
        }
        func blend(_ a: Double, _ b: Double) -> UInt32 {
            UInt32((a + (b - a) * amount).rounded())
        }
        return (blend(channel(lhs, 16), channel(rhs, 16)) << 16)
            | (blend(channel(lhs, 8), channel(rhs, 8)) << 8)
            | blend(channel(lhs, 0), channel(rhs, 0))
    }

    private static func hex(from color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0x2EA043 }
        func channel(_ value: CGFloat) -> UInt32 {
            UInt32((min(1, max(0, value)) * 255).rounded())
        }
        return (channel(r) << 16) | (channel(g) << 8) | channel(b)
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    enum Haptics {
        static func check() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        /// AUSWAHL, nicht Bestätigung — für Gesten, die nur etwas markieren
        /// und nichts schreiben (Tipp auf eine Rasterzelle). Ein
        /// Bestätigungs-Stups an einer Stelle, die gar nichts festmacht,
        /// behauptet einen Vorgang, den es nicht gab.
        static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// EINE Maßskala für die Oberfläche. Alles ist ein Vielfaches von 4, das
    /// meiste von 8; wer hier etwas ändert, verschiebt es überall — genau
    /// dafür stehen die Werte hier und nicht verstreut in den Views.
    ///
    /// `control` ist die wichtigste Zahl: Umschalter-HÖHE, Durchmesser des
    /// zusammengezogenen Blobs und Durchmesser des Anlegen-Knopfes sind
    /// DASSELBE Maß. Geschwisterelemente derselben Ebene dürfen sich in der
    /// Größe nicht unterscheiden, sonst steht das eine optisch höher als das
    /// andere, obwohl beide auf derselben Grundlinie sitzen.
    enum Metrics {
        /// Kantenlänge der schwebenden Bedienelemente unten.
        static let control: CGFloat = 52
        /// Kleinste Trefferfläche (Apple: 44 pt) — auch dort, wo das
        /// Sichtbare kleiner ist.
        static let hit: CGFloat = 44
        /// Native settings rows may grow with Dynamic Type, but never collapse
        /// below a readable control height.
        static let settingsRowMinHeight: CGFloat = 52
        /// Grundabstand.
        static let gap: CGFloat = 8
        /// Spacing between independently interactive settings rows. The
        /// default grouped-list spacing is too compressed with custom glass
        /// backgrounds, so all settings screens use this shared value.
        static let settingsRowGap: CGFloat = 4
        /// Breathing room between settings groups.
        static let settingsSectionGap: CGFloat = 24
        /// Seitenrand von Liste und Chrom.
        static let gutter: CGFloat = 16
        /// Breathing room above a root page's scrollable title.
        static let rootTitleInset: CGFloat = 16
        /// Innenabstand der Rasterfläche.
        static let cardPadding: CGFloat = 12
        /// Eckradius der Rasterfläche.
        static let cardRadius: CGFloat = 16
        /// Kästchen JEDES Chrom-Symbols. Gleich groß, damit die Mittelpunkte
        /// auf einer Linie sitzen; die Punktgrößen darin sind optisch
        /// abgeglichen (siehe ContentView.glyph).
        static let glyph: CGFloat = 32
    }
}

/// Shared contribution tile geometry used by the app graph, GitHub graph,
/// and their previews. The widget extension compiles the GitHub graph without
/// the app-only ContributionGrid file, so the primitive lives in this shared
/// target file.
struct GridCell: View {
    let color: Color
    var size: CGFloat = GridCell.size

    static let radius: CGFloat = 2
    static let size: CGFloat = 12
    static let gap: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// Shared title treatment for the three root tabs. The root navigation title
/// is intentionally empty; this view is the single
/// visible title and scrolls naturally with the page content.
struct RootPageTitle: View {
    static let coordinateSpace = "haiity.root-page-scroll"

    let title: String
    var subtitle: String? = nil
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleHeight: CGFloat = 76

    var body: some View {
        GeometryReader { proxy in
            let offset = proxy.frame(in: .named(Self.coordinateSpace)).minY
            let progress = min(max(-offset / 52, 0), 1)
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 3) {
                Text(title)
                    .font(compact
                          ? .title2.weight(.bold)
                          : .largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !compact {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Metrics.gutter)
            .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.08,
                         anchor: .leading)
            .offset(y: reduceMotion ? 0 : -progress * 7)
            .opacity(1 - progress)
            .accessibilityHidden(progress >= 0.5)
            .preference(key: RootPageTitleProgressKey.self, value: Optional(progress))
        }
        .frame(height: compact ? 44 : titleHeight)
        .accessibilityAddTraits(.isHeader)
    }
}

struct RootPageTitleProgressKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// Compact title shown in the native navigation header after the scrollable
/// title has moved away. Its opacity is driven by the same title progress, so
/// the handoff is one centered title instead of two competing titles.
struct RootPageCompactTitle: View {
    let title: String
    let progress: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(progress)
            .scaleEffect(reduceMotion ? 1 : 0.96 + progress * 0.04)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHidden(progress < 0.5)
    }
}

/// A single, quiet header veil shared by every scrolling page. The material is
/// strongest behind the status and navigation chrome, then dissolves into the
/// page so there is no hard horizontal band below the title.
struct RootPageHeaderBlur: View {
    let progress: CGFloat
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .largeTitle) private var veilHeight: CGFloat = 132

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased
                || Theme.effectiveMaterial(appearancePreferences) == .solid {
                Rectangle().fill(Color(.systemBackground))
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.28),
                        .init(color: .black.opacity(0.62), location: 0.62),
                        .init(color: .black.opacity(0.16), location: 0.84),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            }
            .frame(height: veilHeight)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: – Umgebung

private struct PaletteBookKey: EnvironmentKey {
    static let defaultValue = PaletteBook()
}

extension View {
    /// Farbe und Tint aus dem Store an DIESEN Teilbaum hängen.
    ///
    /// Gebraucht wird das für Blätter: `.sheet` ist eine eigene Präsentation
    /// und erbt die Umgebung des Bildschirms darunter NICHT — die Farbwahl im
    /// Bearbeiten-Blatt zeigte deshalb Grün, während die App in einer eigenen
    /// Farbe lief, und die eigenen Paletten fehlten dort ganz. Eine Zeile je
    /// Blatt, statt in jedem Blatt einzeln daran zu denken.
    func themed(_ store: HabitStore, palettes: PaletteBook? = nil) -> some View {
        let effectivePalettes = palettes ?? store.palettes
        return environment(\.palettes, effectivePalettes)
            .environment(\.appearancePreferences, store.appearancePreferences)
            .tint(Theme.accentText(effectivePalettes.style))
    }

    func appSurface(cornerRadius: CGFloat = Theme.Metrics.cardRadius) -> some View {
        modifier(AppSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// One surface treatment for every settings list and form. Keeping the
    /// list chrome here makes Solid, Milchglas, and Liquid Glass change the
    /// whole settings experience together.
    func settingsSurface() -> some View {
        modifier(SettingsSurfaceModifier())
    }

    /// More uses the same grouped form rhythm as creation and utility sheets.
    func moreSettingsSurface() -> some View {
        modifier(MoreSettingsSurfaceModifier())
    }

    /// Material-backed rows with consistent control insets.
    func moreSettingsSection() -> some View {
        modifier(MoreSettingsSectionModifier())
    }

    /// A compact panel used by the More hub and its non-List editors. It
    /// keeps the selected appearance material while giving the page a clear
    /// rhythm between functional groups.
    func morePanel() -> some View {
        modifier(MorePanelModifier())
    }

    /// iOS 27 can ignore a list-wide row background on grouped lists. Attach
    /// the same surface to the Section that owns the rows so the selected
    /// material is applied at the actual cell boundary.
    func settingsListRow() -> some View {
        // Compatibility name for existing Section call sites.
        settingsRowSurface()
    }

    func settingsRowSurface() -> some View {
        listRowBackground(SettingsRowSurface())
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    /// Chrome for settings screens that are not backed by a `List` or `Form`.
    /// It keeps the page background and navigation bar on the same material
    /// as settings rows when the user changes Solid, Milchglas, or Liquid.
    func settingsChrome() -> some View {
        modifier(SettingsChromeModifier())
    }

    /// Keeps navigation chrome continuous with the selected appearance. The
    /// system otherwise falls back to an opaque large-title band on lists with
    /// a custom background, which is especially visible over an image.
    func navigationChrome() -> some View {
        modifier(NavigationChromeModifier())
    }

    /// Header veil for pages whose title is owned by NavigationStack. The
    /// modifier is separate from `appPageHeader` so modal flows can keep their
    /// compact title while still sharing the same continuous blur and fade.
    func pageHeaderChrome() -> some View {
        modifier(PageHeaderChromeModifier(isVisible: true))
    }

    /// Conditional form used by screens that sometimes own a scrolling title
    /// themselves (for example the More hub and its secondary pages). Keeping
    /// the visibility decision in the shared modifier prevents a second veil
    /// from being painted when the page already has root chrome.
    func pageHeaderChrome(visible: Bool) -> some View {
        modifier(PageHeaderChromeModifier(isVisible: visible))
    }

    /// Applies the same large-title and continuous fade used by full settings
    /// pages. Keeping this in one modifier prevents individual screens from
    /// drifting back to an opaque or inline navigation header.
    func appPageHeader(_ title: String) -> some View {
        modifier(AppPageHeaderModifier(title: title))
    }

    /// Keep scroll edges soft wherever a page meets navigation or bottom
    /// chrome. Older deployment targets simply retain their system behavior.
    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

extension EnvironmentValues {
    /// Die GLOBALE Farbe PLUS die eigenen Paletten. Habit-eigene Farben werden
    /// am Ort des Rasters darübergelegt, nicht hier — sonst würde eine
    /// violette Karte auch die Knöpfe der App violett färben. Die eigenen
    /// Paletten reisen mit, weil eine Habit-Übersteuerung auf eine EIGENE
    /// Farbe zeigen kann und das Raster sie sonst nicht nachschlagen könnte.
    var palettes: PaletteBook {
        get { self[PaletteBookKey.self] }
        set { self[PaletteBookKey.self] = newValue }
    }

    var appearancePreferences: AppearancePreferences {
        get { self[AppearancePreferencesKey.self] }
        set { self[AppearancePreferencesKey.self] = newValue }
    }
}

private struct AppearancePreferencesKey: EnvironmentKey {
    static let defaultValue = AppearancePreferences.default
}

private struct AppearanceBackgroundOwnedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Root page shells set this after mounting the one fixed background. A
    /// nested settings list must then style its rows without painting a
    /// second image/material layer that can move with scrolling.
    var appearanceBackgroundOwned: Bool {
        get { self[AppearanceBackgroundOwnedKey.self] }
        set { self[AppearanceBackgroundOwnedKey.self] = newValue }
    }
}

/// Background and card surfaces share one switch. Liquid Glass falls back to
/// material on older iOS versions, while every mode keeps a subtle readability
/// tint over a user image.
struct AppearanceBackground: View {
    let preferences: AppearancePreferences
    @Environment(\.colorScheme) private var colorScheme
    @State private var preparedImage: UIImage?

    init(preferences: AppearancePreferences) {
        self.preferences = preferences
        _preparedImage = State(initialValue: preferences.backgroundMode == .image
            ? preferences.backgroundImageData.flatMap(AppearanceImageCache.cachedImage)
            : nil)
    }

    private var imageData: Data? {
        guard preferences.backgroundMode == .image else { return nil }
        return preferences.backgroundImageData
    }

    private var imageIdentity: AnyHashable? {
        preferences.backgroundImageIdentity
    }

    private var fallbackColor: Color {
        Theme.color(colorScheme == .dark ? 0x181A18 : 0xF6F5F1)
    }

    private var fallbackGradient: (Color, Color) {
        (fallbackColor, Color(.secondarySystemGroupedBackground))
    }

    var body: some View {
        ZStack {
            switch preferences.backgroundMode {
            case .color:
                preferences.backgroundColorHex.map(Theme.color) ?? fallbackColor
            case .gradient:
                let fallback = fallbackGradient
                LinearGradient(
                    colors: [
                        preferences.gradientStartHex.map(Theme.color) ?? fallback.0,
                        preferences.gradientEndHex.map(Theme.color) ?? fallback.1
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            case .image:
                if let image = preparedImage {
                    let scrim = Theme.effectiveMaterial(preferences) == .adaptive
                        ? Theme.adaptiveBackgroundScrimOpacity(preferences: preferences,
                                                              dark: colorScheme == .dark)
                        : 0.28
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay(Color(.systemBackground).opacity(scrim))
                        .clipped()
                } else {
                    fallbackColor
                }
            }
            if preferences.backgroundMode != .image {
                Color(.systemBackground).opacity(colorScheme == .dark ? 0.08 : 0.04)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: imageIdentity) {
            guard let imageData else { return }
            if let cached = AppearanceImageCache.cachedImage(for: imageData) {
                preparedImage = cached
                return
            }
            preparedImage = nil
            await AppearanceImageCache.prewarm(data: imageData)
            guard !Task.isCancelled else { return }
            preparedImage = AppearanceImageCache.cachedImage(for: imageData)
        }
    }
}

private struct AppSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        Group {
                switch Theme.effectiveMaterial(preferences) {
                case .solid:
                    content.background(Theme.surfaceFill(preferences: preferences), in: shape)
                case .milky:
                    content
                        .background(.regularMaterial, in: shape)
                        .overlay {
                            shape
                                .fill(Theme.surfaceTint(preferences: preferences,
                                                        dark: colorScheme == .dark)
                                    .opacity(Theme.surfaceTintOpacity(preferences: preferences,
                                                                      dark: colorScheme == .dark)))
                                .allowsHitTesting(false)
                        }
                case .liquid:
                    if #available(iOS 26, *) {
                        content
                            .background {
                                Color.clear
                                    .glassEffect(
                                        .regular.tint(Theme.surfaceTint(preferences: preferences,
                                                                        dark: colorScheme == .dark)
                                            .opacity(Theme.surfaceTintOpacity(preferences: preferences,
                                                                              dark: colorScheme == .dark))),
                                        in: shape)
                                    .allowsHitTesting(false)
                            }
                    } else {
                        content
                            .background(.ultraThinMaterial, in: shape)
                            .overlay {
                                shape
                                    .fill(Theme.surfaceTint(preferences: preferences,
                                                            dark: colorScheme == .dark)
                                        .opacity(Theme.surfaceTintOpacity(preferences: preferences,
                                                                          dark: colorScheme == .dark)))
                                    .allowsHitTesting(false)
                            }
                    }
                case .adaptive:
                    let tint = Theme.surfaceTint(preferences: preferences,
                                                 dark: colorScheme == .dark)
                    let opacity = Theme.adaptiveSurfaceOpacity(preferences: preferences,
                                                               dark: colorScheme == .dark)
                    if #available(iOS 26, *) {
                        content
                            .background {
                                Color.clear
                                    .glassEffect(.regular.tint(tint.opacity(opacity)), in: shape)
                                    .allowsHitTesting(false)
                            }
                    } else {
                        content
                            .background(.regularMaterial, in: shape)
                            .overlay {
                                shape
                                    .fill(tint.opacity(opacity))
                                    .allowsHitTesting(false)
                            }
                    }
                }
        }
        .clipShape(shape)
        .overlay {
            shape
                .strokeBorder(Theme.surfaceOutline(preferences: preferences,
                                                    dark: colorScheme == .dark),
                              lineWidth: 0.7)
                .allowsHitTesting(false)
        }
    }
}

struct SettingsRowSurface: View {
    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var material: AppearanceMaterial {
        reduceTransparency || contrast == .increased ? .solid : Theme.effectiveMaterial(preferences)
    }

    private var needsOutline: Bool {
        if #available(iOS 26, *), material == .liquid || material == .adaptive {
            return false // Native glass already supplies its own edge highlight.
        }
        return true
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch material {
                case .solid:
                    rowShape.fill(Theme.surfaceFill(preferences: preferences))
                case .milky:
                    rowShape
                        .fill(.regularMaterial)
                        .overlay {
                            rowShape.fill(Theme.surfaceTint(preferences: preferences,
                                                            dark: colorScheme == .dark)
                                .opacity(Theme.surfaceTintOpacity(preferences: preferences,
                                                                  dark: colorScheme == .dark)))
                        }
                case .liquid:
                    if #available(iOS 26, *) {
                        let tint = Theme.surfaceTint(preferences: preferences,
                                                     dark: colorScheme == .dark)
                        Color.clear.glassEffect(
                            .regular.tint(tint.opacity(colorScheme == .dark ? 0.32 : 0.18)),
                            in: rowShape)
                    } else {
                        rowShape
                            .fill(.regularMaterial)
                            .overlay {
                                rowShape.fill(Color(.systemBackground).opacity(0.16))
                            }
                    }
                case .adaptive:
                    let tint = Theme.surfaceTint(preferences: preferences,
                                                 dark: colorScheme == .dark)
                    if #available(iOS 26, *) {
                        Color.clear.glassEffect(
                            .regular.tint(tint.opacity(Theme.surfaceTintOpacity(
                                preferences: preferences, dark: colorScheme == .dark))),
                            in: rowShape)
                    } else {
                        rowShape
                            .fill(.regularMaterial)
                            .overlay {
                                rowShape.fill(tint.opacity(Theme.surfaceTintOpacity(
                                    preferences: preferences, dark: colorScheme == .dark)))
                            }
                    }
                }
        }
        .clipShape(rowShape)
        .overlay {
            if needsOutline {
                rowShape.strokeBorder(contrast == .increased
                                      ? Color.primary.opacity(0.5)
                                      : Theme.surfaceOutline(preferences: preferences,
                                                             dark: colorScheme == .dark),
                                      lineWidth: contrast == .increased ? 1 : 0.7)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SettingsSurfaceModifier: ViewModifier {
    @ViewBuilder
    private var settingsRowBackground: some View {
        // Sections opt into their own rounded surface. A clear list-wide
        // background prevents a second material layer from tinting the same
        // row differently on iOS 27.
        Color.clear
    }

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .softScrollEdges()
            .listRowSpacing(Theme.Metrics.settingsRowGap)
            .listSectionSpacing(Theme.Metrics.settingsSectionGap)
            .environment(\.defaultMinListRowHeight, Theme.Metrics.settingsRowMinHeight)
            .listRowBackground(settingsRowBackground)
            .listRowSeparator(.hidden)
            .settingsChrome()
    }
}

private struct MoreSettingsSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowSpacing(Theme.Metrics.settingsRowGap)
            .softScrollEdges()
            .listSectionSpacing(Theme.Metrics.settingsSectionGap)
            .environment(\.defaultMinListRowHeight, Theme.Metrics.settingsRowMinHeight)
            .settingsChrome()
    }
}

private struct MoreSettingsSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 12,
                                      leading: Theme.Metrics.gutter,
                                      bottom: 12,
                                      trailing: Theme.Metrics.gutter))
            .listRowBackground(SettingsRowSurface())
            .listRowSeparator(.hidden)
    }
}

private struct MorePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background { SettingsRowSurface() }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                        style: .continuous))
    }
}

private struct NavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        // The page owns the continuous fade. A visible toolbar background
        // adds a second opaque band and makes the header look cut in half.
        content.toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Shared navigation treatment for full pages that are backed by a List or
/// Form. Root tabs use `RootPageTitle` because their title scrolls with the
/// content; these pages use the native large title with the same fading veil.
private struct AppPageHeaderModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .pageHeaderChrome()
    }
}

private struct PageHeaderChromeModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(alignment: .top) {
                if isVisible {
                    RootPageHeaderBlur(progress: 1)
                }
            }
    }
}

private struct SettingsChromeModifier: ViewModifier {
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.appearanceBackgroundOwned) private var appearanceBackgroundOwned

    func body(content: Content) -> some View {
        if appearanceBackgroundOwned {
            content
        } else {
            content.background(AppearanceBackground(preferences: appearancePreferences))
        }
    }
}
