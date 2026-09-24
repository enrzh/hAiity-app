import SwiftUI

/// Say a sentence, see it land in a field, turn it into a habit.
///
/// **The field is real and the keyboard is up.** The transcript is not decoration
/// shown next to a form — it is written into an actual `TextField`, so it can be
/// corrected with the keyboard before anything is created. Speaking is the fast
/// path, not the only path.
///
/// **The draft is shown before it is created.** The sentence "morgens um 7:30
/// Wasser trinken" becomes a name, a time and a kind, and all three are visible
/// first. A habit is a standing commitment, so the person sees what they are
/// agreeing to rather than discovering it in a list afterwards.
struct SpeakToCreateSheet: View {

    let store: HabitStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes

    @State private var dictation = SpeechDictation()
    @State private var text = ""
    @State private var isWorking = false
    @State private var didCreate = false
    @FocusState private var fieldFocused: Bool
    /// The waveform's trail. Sampled here rather than in the recogniser so it
    /// stops the instant the sheet goes away.
    @State private var levels: [Double] = []
    @State private var sampler: Task<Void, Never>?

    private var dark: Bool { scheme == .dark }
    private var accent: Color { Theme.accentText(palettes.style) }

    /// What the current text would become, before anything is created.
    ///
    /// Only the deterministic half — the time out, the rest as the name. The
    /// model runs on confirm, not on every keystroke, because it costs heat and
    /// a person editing a word should not trigger it.
    private var draft: CreateItemDraft? {
        let stripped = CreateItemDraft.stripTime(from: text)
        guard !stripped.name.isEmpty else { return nil }
        return CreateItemDraft(name: stripped.name, emoji: "", minutes: stripped.minutes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.settingsSectionGap) {
                    waveformPanel
                    transcriptField
                    if let draft {
                        draftPreview(draft)
                    }
                    createButton
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.bottom, ChromeLayout.nativeTabBarClearance)
            }
            .scrollIndicators(.hidden)
            .softScrollEdges()
            .settingsChrome()
            .navigationTitle(String(localized: "Aus einem Satz anlegen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Abbrechen")) { close() }
                        .accessibilityIdentifier("speak-to-create-close")
                }
            }
        }
        .onAppear { startListening() }
        .onDisappear { stopEverything() }
        .task {
            // A repeating sample while the sheet is up. Cancelled on disappear,
            // so the recogniser never outlives the UI that draws it.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                guard dictation.state.isListening else { continue }
                levels.append(dictation.level)
                if levels.count > 5 { levels.removeFirst(levels.count - 5) }
            }
        }
    }

    // MARK: - Waveform

    private var waveformPanel: some View {
        VStack(spacing: Theme.Metrics.gap + 6) {
            VoiceWaveform(levels: levels, tint: accent, isActive: dictation.state.isListening)

            // The sheet has to carry its own control, not just hope the tap that
            // opened it started everything: the microphone can be refused, the
            // model can be unavailable, and a person needs to stop and start
            // again. The status line promises this button, so it has to exist.
            Button {
                toggleListening()
            } label: {
                Image(systemName: dictation.state.isListening ? "stop.fill" : "mic.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.Metrics.control, height: Theme.Metrics.control)
                    .background(listeningTint, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canToggleListening)
            .opacity(canToggleListening ? 1 : 0.4)
            .accessibilityLabel(dictation.state.isListening
                                ? String(localized: "Aufnahme beenden")
                                : String(localized: "Aufnahme starten"))
            .accessibilityIdentifier("speak-to-create-toggle")
            .padding(.top, 2)

            Text(statusLine)
                .font(.footnote)
                .foregroundStyle(statusIsProblem ? .orange : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Metrics.settingsSectionGap)
        .appSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("speak-to-create-waveform")
    }

    private var statusLine: String {
        switch dictation.state {
        case .idle where !text.isEmpty:
            return String(localized: "Fertig. Du kannst den Text unten noch ändern.")
        case .idle:
            return String(localized: "Tippe auf den Knopf und sprich.")
        case .requestingPermission:
            return String(localized: "Warten auf Erlaubnis …")
        case .denied:
            return String(localized: "Ohne Mikrofon geht es nicht. Du kannst den Text unten auch tippen.")
        case .unavailable(let reason):
            return reason
        case .listening:
            return text.isEmpty
                ? String(localized: "Ich höre zu …")
                : String(localized: "Ich höre zu … tippe zum Stoppen.")
        case .failed(let reason):
            return reason
        }
    }

    private var listeningTint: Color {
        dictation.state.isListening ? accent : accent.opacity(0.55)
    }

    /// Nothing to toggle while the recogniser is unavailable or refused — the
    /// field below still works, so the button is visibly out of play rather than
    /// silently doing nothing.
    private var canToggleListening: Bool {
        switch dictation.state {
        case .denied, .unavailable, .failed: return false
        case .idle, .requestingPermission, .listening: return true
        }
    }

    private func toggleListening() {
        if dictation.state.isListening {
            dictation.stop()
        } else {
            levels = []
            Task { await dictation.start() }
        }
    }

    private var statusIsProblem: Bool {
        switch dictation.state {
        case .denied, .failed, .unavailable: return true
        default: return false
        }
    }

    // MARK: - Transcript

    private var transcriptField: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Text(String(localized: "Dein Satz"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            // A real field, focused, with the native keyboard up: the transcript
            // can be corrected by hand and the mic on that keyboard still works
            // for anyone who would rather use the system's dictation.
            TextField(String(localized: "Was möchtest du tracken?"), text: $text, axis: .vertical)
                .lineLimit(3...6)
                .focused($fieldFocused)
                .textFieldStyle(.plain)
                .font(.body)
                .accessibilityIdentifier("speak-to-create-text")
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface()
    }

    // MARK: - Draft

    @ViewBuilder
    private func draftPreview(_ draft: CreateItemDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Text(String(localized: "Daraus wird"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Metrics.gap + 4) {
                AppIconBadge(symbol: draft.kind == .reminder ? "bell" : "checkmark.circle")
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(draftSubtitle(draft))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("speak-to-create-draft")
    }

    private func draftSubtitle(_ draft: CreateItemDraft) -> String {
        var parts = [draft.kind == .reminder
                     ? String(localized: "Erinnerung")
                     : String(localized: "Habit")]
        if let minutes = draft.minutes {
            parts.append(String(format: String(localized: "um %02d:%02d"),
                                minutes / 60, minutes % 60))
        }
        parts.append(String(localized: "täglich"))
        return parts.joined(separator: " · ")
    }

    // MARK: - Create

    private var createButton: some View {
        Button {
            Task { await create() }
        } label: {
            HStack(spacing: Theme.Metrics.gap) {
                if isWorking { ProgressView() }
                Text(didCreate
                     ? String(localized: "Angelegt")
                     : String(localized: "Anlegen"))
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit)
        }
        .buttonStyle(.borderedProminent)
        .disabled(draft == nil || isWorking || didCreate)
        .accessibilityIdentifier("speak-to-create-confirm")
    }

    private func create() async {
        guard var draft, !didCreate else { return }
        isWorking = true
        defer { isWorking = false }

        // The model is asked only here, once, because the person pressed the
        // button. Without it the deterministic read of the sentence still
        // produces a usable name and time.
        let full = await CreateItemDraft.read(from: text)
        if !full.name.isEmpty { draft = full }

        switch await CreateItemSaver.save(draft) {
        case .saved:
            didCreate = true
            stopEverything()
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        case .emptyName:
            stopEverything()
        case .limitReached:
            stopEverything()
        }
    }

    // MARK: - Lifecycle

    /// Opening the sheet focuses the field and leaves the microphone closed.
    /// Auto-starting would put a permission prompt in front of someone who
    /// opened the sheet to type, and the button would then be a stop button
    /// nobody asked for.
    private func startListening() {
        fieldFocused = true
    }

    private func stopEverything() {
        sampler?.cancel()
        sampler = nil
        dictation.stop()
        levels = []
    }

    private func close() {
        stopEverything()
        dismiss()
    }
}
