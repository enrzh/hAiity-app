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
    /// The model's reading of the sentence, and the exact text it was made
    /// from. Kept apart because a reading belongs to one sentence: edit a word
    /// and it is stale, and saving a stale reading means saving something the
    /// person never saw.
    @State private var readDraft: CreateItemDraft?
    @State private var readFrom = ""
    @State private var isReading = false
    @FocusState private var fieldFocused: Bool
    /// The waveform's trail. Sampled here rather than in the recogniser so it
    /// stops the instant the sheet goes away.
    @State private var levels: [Double] = []
    @State private var sampler: Task<Void, Never>?

    private var dark: Bool { scheme == .dark }
    private var accent: Color { Theme.accentText(palettes.style) }

    /// What pressing "Anlegen" would create right now.
    ///
    /// A reading is used only while it still matches the text. Otherwise this is
    /// the deterministic half alone: the name, and a time if the sentence had
    /// one. The model is never run from here — it costs heat, so it runs when
    /// the person asks for it, and not on every keystroke.
    private var draft: CreateItemDraft? {
        if let readDraft, readFrom == text { return readDraft }
        let stripped = CreateItemDraft.stripTime(from: text)
        guard !stripped.name.isEmpty else { return nil }
        return CreateItemDraft(name: stripped.name, emoji: "", minutes: stripped.minutes)
    }

    /// Whether what is on screen came from this exact sentence, or is only the
    /// part that can be known without asking.
    private var needsReading: Bool { readDraft == nil || readFrom != text }

    private var hasSentence: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canRead: Bool {
        OnDeviceModel.isAvailable && hasSentence && !isReading && !isWorking
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
        .onChange(of: dictation.transcript) { _, spoken in
            // The recogniser owns the text while it is running. Without this the
            // recognised words landed in `SpeechDictation.transcript` and never
            // reached the field, so the sheet looked like it was hearing nothing
            // at all. A partial result replaces what is there, so a correction
            // shows up as it is made rather than only at the end.
            guard dictation.state.isListening, !spoken.isEmpty else { return }
            text = spoken
        }
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
            stopEverything()
        } else {
            // Starting over replaces the sentence. Anything typed by hand stays
            // until the person asks to record again, at which point their
            // intention is unambiguous.
            text = ""
            dictation.reset()
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
                // The emoji the model picked, once there is one. Before that the
                // kind carries the badge, so the row never sits there empty.
                if draft.emoji.isEmpty {
                    AppIconBadge(symbol: draft.kind == .reminder ? "bell" : "checkmark.circle")
                } else {
                    Text(draft.emoji)
                        .font(.body)
                        .frame(width: Theme.Metrics.glyph, height: Theme.Metrics.glyph)
                        .background(accent.opacity(0.11), in: Circle())
                        .accessibilityHidden(true)
                }
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
            if OnDeviceModel.isAvailable { readRow }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("speak-to-create-draft")
    }

    /// The one control that spends heat, so it says so.
    ///
    /// The reading is a separate, visible step rather than something tucked
    /// inside "Anlegen" for two reasons: the person decides when the device gets
    /// warm, and they get to see and change what the model made of the sentence
    /// before it becomes a habit they have to delete.
    private var readRow: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Button {
                Task { await read() }
            } label: {
                HStack(spacing: Theme.Metrics.gap) {
                    if isReading { ProgressView() }
                    Text(readDraft == nil
                         ? String(localized: "Satz lesen")
                         : String(localized: "Neu lesen"))
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canRead)
            .accessibilityIdentifier("speak-to-create-read")

            Text(needsReading
                 ? String(localized: "Liest Name, Symbol und Wiederholung aus dem Satz. Das Gerät wird dabei wärmer, also nur wenn du es möchtest.")
                 : String(localized: "Gelesen. Ändere den Satz, und du kannst ihn neu lesen."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func draftSubtitle(_ draft: CreateItemDraft) -> String {
        var parts = [draft.kind == .reminder
                     ? String(localized: "Erinnerung")
                     : String(localized: "Habit")]
        if let minutes = draft.minutes {
            parts.append(String(format: String(localized: "um %02d:%02d"),
                                minutes / 60, minutes % 60))
        }
        // The repeat only once it has actually been read. Printing "Jeden Tag"
        // here would be a guess dressed up as a result: the create button reads
        // the sentence, and that is where the repeat comes from, so the preview
        // would promise daily and the list would show Mondays.
        if needsReading, OnDeviceModel.isAvailable {
            parts.append(String(localized: "Wiederholung noch offen"))
        } else {
            parts.append(RecurrenceText.pattern(draft.schedule.recurrence))
        }
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

    /// Ask the model what the sentence means, once, because the person pressed
    /// the button.
    private func read() async {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !isReading else { return }
        isReading = true
        defer { isReading = false }
        readDraft = await CreateItemDraft.read(from: sentence)
        // Recorded after the await, so a sentence edited while the model was
        // working is not quietly claimed to have been read.
        readFrom = text
    }

    private func create() async {
        guard let draft, !didCreate else { return }
        isWorking = true
        defer { isWorking = false }

        // A reading the person already asked for is reused rather than paid for a
        // second time. Only an unread sentence is read now, which is also what
        // keeps this from being a hidden second model call.
        let final = needsReading ? await CreateItemDraft.read(from: text) : draft

        switch await CreateItemSaver.save(final, into: store) {
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
        // The final result can arrive after listening has ended, so take the
        // transcript first; `stop()` clears the listening state and the
        // live-sync above would then refuse it.
        if !dictation.transcript.isEmpty { text = dictation.transcript }
        dictation.stop()
        levels = []
    }

    private func close() {
        stopEverything()
        dismiss()
    }
}
