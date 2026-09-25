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
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                // Room for the dock to float over the last card without ever
                // covering it, and the home-indicator inset beneath that.
                .padding(.bottom, dockClearance)
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
            .safeAreaInset(edge: .bottom, spacing: 0) { dock }
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

    /// Pure content now: the shape of what was heard, and what is going on.
    ///
    /// The microphone used to sit in here, inside a content card. It moved to the
    /// floating dock, which is the only layer the material is allowed on and the
    /// only place a control belongs when it has to be reachable one-handed. What
    /// is left is the part that is genuinely content, so this panel is an ordinary
    /// opaque surface.
    private var waveformPanel: some View {
        VStack(spacing: Theme.Metrics.gap + 6) {
            VoiceWaveform(levels: levels, tint: accent, isActive: dictation.state.isListening)

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
            // Before a reading, this card is showing the sentence with the clock
            // time lifted out — not a finished name. Calling it "Daraus wird"
            // would promise a name and a repeat that nobody has worked out yet.
            Text(needsReading && OnDeviceModel.isAvailable
                 ? String(localized: "Satz, noch nicht gelesen")
                 : String(localized: "Daraus wird"))
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

    // MARK: - The floating dock

    @Namespace private var glassNamespace

    /// How much room the dock needs underneath the scrolling content.
    private var dockClearance: CGFloat {
        ChromeLayout.nativeTabBarClearance + Theme.Metrics.control + Theme.Metrics.gap * 2
    }

    /// The sheet's one piece of glass.
    ///
    /// Liquid Glass belongs to the floating functional layer, never to content —
    /// so the waveform panel, the text field and the draft stay ordinary opaque
    /// surfaces, and the glass is spent on the two controls that actually float
    /// above the scroll. Both live in one `GlassEffectContainer` and share a
    /// `glassEffectUnion`, so iOS draws them as ONE shape that morphs rather than
    /// as two panes of blur sitting next to each other. Glass stacked on glass is
    /// the exact thing the material exists to avoid.
    private var dock: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: Theme.Metrics.gap) { dockRow }
            } else {
                dockRow
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.bottom, Theme.Metrics.gap)
        // A whisper of a background so the glass has something to sample. Fully
        // clear, because a real fill here would turn the dock into a second card.
        .background(Color(.systemBackground).opacity(0.001))
    }

    private var dockRow: some View {
        HStack(spacing: Theme.Metrics.gap) {
            micControl
            createControl
        }
    }

    /// The microphone, out of the waveform panel and down into the dock.
    ///
    /// It was a button living inside a content card, which is the one place the
    /// material must not go. Here it is a control that floats over the content,
    /// within thumb reach of the primary action beside it. Neutral glass while
    /// idle, so the one coloured control in the sheet stays the one people mean.
    private var micControl: some View {
        Button {
            toggleListening()
        } label: {
            Image(systemName: dictation.state.isListening ? "stop.fill" : "mic.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dictation.state.isListening ? Color.white : accent)
                .frame(width: Theme.Metrics.control, height: Theme.Metrics.control)
                .contentShape(Circle())
                .modifier(ChromeGlass(id: "speak-dock-mic",
                                      namespace: glassNamespace,
                                      kind: .circle,
                                      union: dockUnion))
        }
        .buttonStyle(.plain)
        .disabled(!canToggleListening)
        .opacity(canToggleListening ? 1 : 0.4)
        .accessibilityLabel(dictation.state.isListening
                            ? String(localized: "Aufnahme beenden")
                            : String(localized: "Aufnahme starten"))
        .accessibilityIdentifier("speak-to-create-toggle")
    }

    /// The primary action, tinted rather than plain glass — colour on the
    /// background is how the system marks the action someone most likely wants.
    private var createControl: some View {
        Button {
            Task { await create() }
        } label: {
            HStack(spacing: Theme.Metrics.gap) {
                if isWorking { ProgressView().tint(.white) }
                Text(didCreate
                     ? String(localized: "Angelegt")
                     : String(localized: "Anlegen"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.control)
            .contentShape(Rectangle())
            .modifier(ChromeGlass(id: "speak-dock-create",
                                  namespace: glassNamespace,
                                  kind: .capsule,
                                  accent: palettes.style,
                                  union: dockUnion))
        }
        .buttonStyle(.plain)
        .disabled(draft == nil || isWorking || didCreate)
        .opacity(draft == nil ? 0.5 : 1)
        .accessibilityIdentifier("speak-to-create-confirm")
    }

    /// One identifier for both shapes. That is what tells iOS they are a single
    /// surface rather than two.
    private var dockUnion: String { "speak-dock" }

    /// Ask the model what the sentence means, once, because the person pressed
    /// the button.
    private func read() async {
        // Captured before the await, and recorded afterwards against this exact
        // string. Reading the field again on the way back would stamp a reading
        // of the OLD sentence with the NEW text, mark it fresh, and save a draft
        // for words the person has already changed.
        let requested = text
        guard !requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isReading else { return }
        isReading = true
        defer { isReading = false }
        readDraft = await CreateItemDraft.read(from: requested)
        readFrom = requested
    }

    private func create() async {
        guard let draft, !didCreate else { return }
        isWorking = true
        defer { isWorking = false }

        // A reading the person already asked for is reused rather than paid for a
        // second time. Only an unread sentence is read now, which is also what
        // keeps this from being a hidden second model call.
        let sentence = text
        let final = needsReading ? await CreateItemDraft.read(from: sentence) : draft

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
