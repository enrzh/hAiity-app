import SwiftUI

/// A row of bars that react to the microphone.
///
/// **Why it is not the Siri orb.** Apple's HIG reserves Siri's own look and
/// tells apps never to reproduce it (`siri.md` › Editorial guidelines). The
/// rhythm here is the same idea — bars that move with a voice — drawn in the
/// app's own accent, so it reads as *hAiity is listening* and never as a system
/// control. No orb, no rainbow, no "Hey" anything.
///
/// **Why the bars are history, not a meter.** A single level value makes every
/// bar identical, which looks like a progress bar. Keeping a short trail of
/// recent levels gives each bar its own value and reads as a waveform, which is
/// what tells someone the thing is actually hearing them.
struct VoiceWaveform: View {

    /// The most recent levels, oldest first. Short on purpose: a long tail turns
    /// into a scrolling graph rather than a voice.
    let levels: [Double]
    var barCount: Int = 5
    var tint: Color
    /// A calm baseline when nothing is arriving, so the control is not dead
    /// between words.
    var isActive: Bool = true

    private var visible: [Double] {
        guard !levels.isEmpty else {
            return Array(repeating: isActive ? 0.12 : 0.06, count: barCount)
        }
        return Self.trail(levels: levels, level: levels.last ?? 0, barCount: barCount)
    }

    /// The trail a caller should pass for a given level, oldest first.
    ///
    /// Pure, so the shape of the waveform can be tested without a microphone.
    static func trail(levels: [Double], level: Double, barCount: Int) -> [Double] {
        let combined = levels + [level]
        let recent = Array(combined.suffix(barCount))
        guard let first = recent.first else {
            return Array(repeating: 0.12, count: barCount)
        }
        return Array(repeating: first, count: max(0, barCount - recent.count)) + recent
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(tint.opacity(index == visible.count - 1 ? 1 : 0.55))
                    .frame(width: 3,
                           // The centre bar is the tallest, so the shape stays
                           // recognisable at small sizes.
                           height: max(4, CGFloat(0.28 + value * 0.72) * 28))
            }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }
}
