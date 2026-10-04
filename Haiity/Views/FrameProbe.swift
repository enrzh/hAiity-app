#if DEBUG
import QuartzCore
import Foundation

/// Bildzeit-Messung für die Diagnose — NUR im Debug-Build und nur, wenn die
/// App mit `-frame-probe` gestartet wurde. Kein Ersatz für Instruments, aber
/// das, was Instruments auf einem Simulator hier nicht liefert: pro Sekunde
/// eine Zeile mit der Anzahl Bilder, dem schlechtesten Abstand und den
/// Zählern, die sagen, WAS in dieser Sekunde wie oft gerechnet wurde.
///
/// Zwei Zahlen entscheiden:
///  * `worst`/`late` — die Symptomseite (ruckelt es?),
///  * die Zähler — die Ursachenseite (wie oft wurde ein Teilbaum neu
///    ausgewertet, während EIN Zug lief?).
final class FrameProbe: @unchecked Sendable {
    static let shared = FrameProbe()

    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-frame-probe") }

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var worst: Double = 0
    private var late = 0
    private var counters: [String: Int] = [:]
    private let lock = NSLock()

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        last = CACurrentMediaTime()
        windowStart = last
    }

    /// Ein Ereignis mitzählen (Body-Auswertung, Layout-Rechnung …).
    ///
    /// Der Schnellausgang steht ganz vorn: die Marken sitzen in `body`-
    /// Auswertungen, und ein Mutex pro Bild und Ansicht wäre selbst eine
    /// Messgröße. Ohne `-frame-probe` kostet das hier einen Bool-Vergleich.
    func mark(_ what: String) {
        guard active else { return }
        lock.lock(); counters[what, default: 0] += 1; lock.unlock()
    }

    private let active = FrameProbe.enabled

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let delta = now - last
        last = now
        frames += 1
        if delta > worst { worst = delta }
        // Use the active display interval, including adaptive refresh rates.
        let interval = max(link.targetTimestamp - link.timestamp, link.duration)
        if interval > 0, delta > interval * 1.5 { late += 1 }
        guard now - windowStart >= 1 else { return }
        lock.lock()
        let snapshot = counters.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        counters.removeAll()
        lock.unlock()
        print(String(format: "FRAMEPROBE frames=%d late=%d worst=%.1fms %@",
                     frames, late, worst * 1000, snapshot))
        frames = 0; late = 0; worst = 0
        windowStart = now
    }
}
#endif
