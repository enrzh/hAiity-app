import SwiftUI

/// Type a sentence, see it parsed, turn it into a habit.
///
/// **The field is real and the keyboard is up.** The sentence is written into an
/// actual `TextField`, so it can be corrected before anything is created.
///
/// **There is no microphone in here.** Dictation is the keyboard's job: the
/// system key under the caret does the same thing, in the user's own language,
/// under the system's own consent prompt — and it costs the app neither a
/// microphone nor a speech-recognition permission. Carrying our own recogniser
/// meant a second permission, a second privacy promise, and a worse transcript
/// than the one already sitting under the caret.
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
    /// Half a page while there is nothing to decide, the full page once the
    /// sentence is in and the draft has to be looked at.
    @State private var detent: PresentationDetent = .fraction(0.5)
    @FocusState private var fieldFocused: Bool
    /// The model on this device, and the reader that runs it. Optional: a person
    /// who has not downloaded anything still gets Apple's model where it exists
    /// and the deterministic reading everywhere else.
    @State private var modelService = LocalModelService()
    @State private var localReader = LocalModelSentenceReader(service: LocalModelService())

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

    private var hasUsableReader: Bool {
        OnDeviceModel.isAvailable || hasDownloadedModel
    }

    /// Reading is possible when EITHER model can answer.
    ///
    /// Gating on Apple's Foundation Models alone hid the button on every device
    /// below iOS 26 and in the simulator, which made a downloaded model look
    /// like it did nothing. The two are alternatives, not a preference order.
    private var canRead: Bool {
        hasUsableReader && hasSentence && !isReading && !isWorking
    }

    /// Whether a model is on the phone, refreshed when the sheet opens.
    @State private var hasDownloadedModel = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Metrics.settingsSectionGap) {
                    promptPanel
                    transcriptField
                    // The draft only exists at the full height.
                    //
                    // It used to appear at half too, which is where the trouble
                    // started: the sheet is for LISTENING at half, the draft card
                    // does not fit, and arriving there scrolled the content up
                    // under a transparent navigation bar — so the sentence being
                    // spoken showed through "Abbrechen" and the title while
                    // someone was still talking. Half is the waveform and the
                    // sentence; the full page is where the reading gets reviewed.
                    if let draft, detent == .large {
                        draftPreview(draft)
                    }
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .id("speak-content")
            }
            .scrollIndicators(.hidden)
            // The dock floats, so the content has to be able to move out from
            // under it. The inset alone was not enough once the keyboard was up
            // inside a half-height sheet: the draft card ended up underneath the
            // dock with its last line sliced off. This is a scroll-content margin
            // rather than padding, so it survives the viewport shrinking.
            .contentMargins(.bottom, dockClearance, for: .scrollContent)
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
            // Half a page to begin with, and the full page when there is something
            // to look at. A grabber is there so it can also be dragged by hand,
            // and the page behind stays live at the short detent — which is the
            // point of a half sheet: you can see what you are adding to.
            .presentationDetents([.fraction(0.5), .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
            .presentationCornerRadius(CornerRadius.hero)
            // Only once the sheet is at the full height AND there is a draft.
            // Both have to be watched: expanding happens when the field is
            // focused, which is before a single word has been typed, so listening
            // to the height alone fired the scroll against a nil draft and never
            // ran. And watching the draft alone was the original bug — it scrolled
            // the listening surface out of view and up under the bar.
            .onChange(of: detent) { _, _ in scrollDraftIntoView(proxy) }
            .onChange(of: draft != nil) { _, _ in scrollDraftIntoView(proxy) }
            .onChange(of: text) { _, _ in scrollDraftIntoView(proxy) }
            }
        }
        .onAppear {
            fieldFocused = true
            // The page may have downloaded a model since this sheet's service was
            // built, so the disk is the authority.
            modelService.refresh()
            hasDownloadedModel = LocalModelCatalogue.all.contains {
                modelService.registry.state(for: $0.id).isReady
            }
        }
        .onDisappear {
            // A model holds hundreds of megabytes of weight cache. Keeping it
            // between sheets makes the rest of the app feel heavier than it is.
            localReader.release()
        }
        // Tapping the text is a request to edit, which also needs the room.
        .onChange(of: fieldFocused) { _, focused in
            if focused { expandForReview() }
        }
    }

    // MARK: - Prompt

    /// What to put where the waveform used to be.
    ///
    /// The panel used to draw what the microphone was hearing. There is no
    /// microphone now, so the space earns its keep by saying the one thing a
    /// person arriving here does not know: dictation is still available, one key
    /// away, on the keyboard under the caret.
    private var promptPanel: some View {
        VStack(spacing: Theme.Metrics.gap + 6) {
            Image(systemName: "text.badge.plus")
                .font(.title2)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(statusLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("speak-to-create-prompt")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Metrics.gap + 8)
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .appSurface()
    }

    // MARK: - Waveform

    /// Pure content now: the shape of what was heard, and what is going on.
    ///
    /// What is going on, in one line.
    ///
    /// There is no listening state any more, so this is the sentence being typed
    /// or not. It names the keyboard's dictation key, because that is the part
    /// someone arriving from the old in-app microphone will miss.
    private var statusLine: String {
        if text.isEmpty {
            return String(localized: "Tippe deinen Satz ein. Mit der Diktier-Taste der Tastatur geht es auch mit Sprache.")
        }
        return String(localized: "Fertig. Du kannst den Text unten noch ändern.")
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
        .appCard()
    }

    // MARK: - Draft

    @ViewBuilder
    private func draftPreview(_ draft: CreateItemDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            // Before a reading, this card is showing the sentence with the clock
            // time lifted out — not a finished name. Calling it "Daraus wird"
            // would promise a name and a repeat that nobody has worked out yet.
            Text(needsReading && hasUsableReader
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
            if hasUsableReader { readRow }
        }
        .appCard()
        // `.contain`, not `.combine`. The card holds the "Satz lesen" button,
        // and combining folded that button into the card's own accessibility
        // element — so the one control that spends the model and the heat was
        // not a control any more. Assistive technology could not reach it or
        // activate it, and a synthetic tap resolved to the wrong frame and
        // landed on the microphone instead. `.contain` still groups the card as
        // one place while leaving the button itself reachable.
        .accessibilityElement(children: .contain)
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
        if needsReading, hasUsableReader {
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

    /// The sheet's one piece of glass: a single bar, not two floating pills.
    ///
    /// The first attempt put a glass circle and a glass capsule in an HStack and
    /// asked a `glassEffectUnion` to merge them. It does not work: a union joins
    /// shapes that are already touching, and these had a gap between them, so the
    /// result was two distant circles floating over the wallpaper with no dock
    /// around them. One bar is also the correct reading of the material — a
    /// bottom action bar is a functional-layer element, and the glass is on the
    /// bar, not on the two controls inside it. Glass on glass is what the material
    /// exists to avoid, so nothing inside here is glass.
    private var dock: some View {
        HStack(spacing: Theme.Metrics.gap) {
            createControl
        }
        .padding(Theme.Metrics.gap)
        .frame(maxWidth: .infinity)
        .modifier(ChromeGlass(id: "speak-dock",
                              namespace: glassNamespace,
                              kind: .bar,
                              union: dockUnion))
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.bottom, Theme.Metrics.gap)
    }

    /// The primary action, and the one coloured control in the sheet. A filled
    /// capsule rather than glass, so it reads as the action against the bar.
    ///
    /// Disabled, it goes neutral rather than fading the accent. A pale green
    /// button at half opacity looks like a rendering mistake; a grey one looks
    /// like what it is.
    private var createControl: some View {
        let ready = draft != nil && !isWorking && !didCreate
        return Button {
            Task { await create() }
        } label: {
            HStack(spacing: Theme.Metrics.gap) {
                if isWorking { ProgressView().tint(.white) }
                Text(didCreate
                     ? String(localized: "Angelegt")
                     : String(localized: "Anlegen"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ready ? Color.white : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.control)
            .background(ready
                        ? AnyShapeStyle(Theme.accentFill(palettes.style))
                        : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityIdentifier("speak-to-create-confirm")
    }

    /// One identifier for the bar. Nothing else in the sheet claims glass.
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
        if hasDownloadedModel {
            // The chosen model is on this device, so it is the one that answers.
            switch await localReader.read(requested) {
            case .draft(let parsed):
                readDraft = parsed
                readFrom = requested
                return
            case .unreadable, .failed:
                // Fall through to Apple's model and then to the deterministic
                // reading, rather than leaving the person with nothing. A model
                // that cannot answer must not be the end of the road.
                readDraft = nil
            }
        }
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
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        case .emptyName:
            break
        case .limitReached:
            break
        }
    }

    // MARK: - Lifecycle

    /// The dock floats, so content passes under it by design — what must not
    /// happen is the draft coming to rest half-sliced by it.
    ///
    /// Both conditions are required. The full height, because half is the
    /// listening surface and scrolling there moved the waveform and the sentence
    /// out of view. And a draft, because watching only the height fired the scroll
    /// against a nil draft — expanding happens when the field is focused, which is
    /// before a word has been typed — so nothing moved at all.
    private func scrollDraftIntoView(_ proxy: ScrollViewProxy) {
        guard detent == .large, draft != nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo("speak-content", anchor: .bottom)
        }
    }

    /// Give the sheet its full height once there is a sentence to work on.
    ///
    /// Called when dictation finishes and when the field is focused. A half sheet
    /// is right for listening and wrong for deciding what a sentence became, so
    /// the sheet grows the moment that changes.
    private func expandForReview() {
        guard detent != .large else { return }
        detent = .large
    }

    private func close() {
        dismiss()
    }
}
