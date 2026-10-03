import SwiftUI

/// Type or dictate a sentence, review its schedule, then save the displayed draft.
struct SpeakToCreateSheet: View {

    let store: HabitStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palettes) private var palettes
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var text = ""
    @State private var isWorking = false
    @State private var didCreate = false
    @State private var saveError: String?
    @State private var dictation = SpeechDictation.makeForCreationInput()
    @State private var dictationPrefix = ""
    @State private var dictationTask: Task<Void, Never>?
    @State private var resumeEditingAfterDictation = false
    @State private var referenceNow = Date()
    @State private var isVisible = false
    @State private var workTask: Task<Void, Never>?
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

    private var accent: Color { Theme.accentText(palettes.style) }
    private var calendar: Calendar {
        var value = HabitTimeZone.calendar(identifier: store.defaultTimeZoneIdentifier)
        value.locale = locale
        return value
    }

    /// What pressing "Anlegen" would create right now.
    ///
    /// Models run only after a tap; explicit dates/times are available immediately.
    private var draft: CreateItemDraft? {
        if let readDraft, readFrom == text { return readDraft }
        guard hasSentence else { return nil }
        return CreateItemDraft.fallback(from: text, locale: locale,
                                        calendar: calendar, now: referenceNow)
    }

    /// Whether what is on screen came from this exact sentence, or is only the
    /// part that can be known without asking.
    private var needsReading: Bool { readDraft == nil || readFrom != text }
    private var requiresReading: Bool {
        needsReading && hasUsableReader && draft?.schedule.frequency != .once
    }

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
            && !dictation.state.isActive && draft?.validationMessage == nil
    }

    /// Whether a model is on the phone, refreshed when the sheet opens.
    @State private var hasDownloadedModel = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Metrics.settingsSectionGap) {
                    if !hasSentence { promptPanel }
                    transcriptField
                    // A draft needs the full detent to remain clear of the dock.
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
            }
        }
        .onAppear {
            isVisible = true
            referenceNow = Date()
            fieldFocused = true
            // The page may have downloaded a model since this sheet's service was
            // built, so the disk is the authority.
            modelService.refresh()
            hasDownloadedModel = LocalModelCatalogue.all.contains {
                modelService.registry.state(for: $0.id).isReady
            }
        }
        .onDisappear {
            isVisible = false
            workTask?.cancel()
            dictationTask?.cancel()
            dictation.cancel()
            // A model holds hundreds of megabytes of weight cache. Keeping it
            // between sheets makes the rest of the app feel heavier than it is.
            localReader.release()
        }
        .alert(String(localized: "Fehler"), isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button(String(localized: "OK"), role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        // Tapping the text is a request to edit, which also needs the room.
        .onChange(of: fieldFocused) { _, focused in
            if focused {
                dictationTask?.cancel()
                if dictation.state == .listening {
                    resumeEditingAfterDictation = true
                    fieldFocused = false
                    dictation.stop()
                } else if dictation.state == .finalizing {
                    resumeEditingAfterDictation = true
                    fieldFocused = false
                } else {
                    dictation.cancel()
                }
                expandForReview()
            }
        }
        .onChange(of: dictation.transcript) { _, transcript in
            guard isVisible, !fieldFocused else { return }
            text = SpeechDictation.mergedTranscript(prefix: dictationPrefix, transcript: transcript)
        }
        .onChange(of: dictation.state) { old, new in
            guard isVisible, old.isActive, !new.isActive else { return }
            text = SpeechDictation.mergedTranscript(prefix: dictationPrefix, transcript: dictation.transcript)
            if resumeEditingAfterDictation {
                resumeEditingAfterDictation = false
                fieldFocused = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                workTask?.cancel()
                dictationTask?.cancel()
                resumeEditingAfterDictation = false
                dictation.cancel()
            }
        }
        .onChange(of: store.defaultTimeZoneIdentifier) { _, _ in
            readDraft = nil
            workTask?.cancel()
        }
        .onChange(of: locale) { _, _ in
            readDraft = nil
            workTask?.cancel()
        }
        .interactiveDismissDisabled(isWorking)
    }

    // MARK: - Prompt

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

    // MARK: - Input status

    private var statusLine: String {
        switch dictation.state {
        case .requestingPermission:
            return String(localized: "Diktat wird vorbereitet...")
        case .listening:
            return String(localized: "Diktiert... Tippe auf Stopp, wenn du fertig bist.")
        case .finalizing:
            return String(localized: "Diktat wird abgeschlossen...")
        case .denied:
            return String(localized: "Diktieren ist nicht erlaubt. Du kannst weiter tippen oder den Zugriff in den iOS-Einstellungen erlauben.")
        case .unavailable(let message), .failed(let message):
            return message
        case .idle:
            return text.isEmpty
                ? String(localized: "Tippe deinen Satz ein oder nutze das Mikrofon im Textfeld.")
                : String(localized: "Prüfe Datum und Uhrzeit. Du kannst den Satz noch ändern.")
        }
    }

    // MARK: - Transcript

    private var transcriptField: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Text(String(localized: "Dein Satz"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: Theme.Metrics.gap) {
                TextField(String(localized: "Was möchtest du tracken?"), text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($fieldFocused)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .disabled(isWorking || dictation.state == .requestingPermission
                              || dictation.state == .finalizing)
                    .accessibilityIdentifier("speak-to-create-text")
                dictationControl
            }
            if hasSentence, dictation.state != .idle {
                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("speak-to-create-prompt")
            }
            if let message = draft?.validationMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("speak-to-create-validation")
            }
        }
        .appCard()
    }

    private var dictationControl: some View {
        Button {
            toggleDictation()
        } label: {
            Group {
                if dictation.state == .requestingPermission || dictation.state == .finalizing {
                    ProgressView()
                } else {
                    Image(systemName: dictation.state == .listening ? "stop.fill" : "mic")
                        .font(.body)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemFill), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(isReading || isWorking || dictation.state == .finalizing)
        .accessibilityLabel(dictation.state.isActive
                            ? String(localized: "Diktat beenden")
                            : String(localized: "Diktieren"))
        .accessibilityValue(statusLine)
        .accessibilityIdentifier("speak-to-create-dictation")
    }

    // MARK: - Draft

    @ViewBuilder
    private func draftPreview(_ draft: CreateItemDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            // Before a reading, this card is showing the sentence with the clock
            // time lifted out — not a finished name. Calling it "Daraus wird"
            // would promise a name and a repeat that nobody has worked out yet.
            Text(requiresReading
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
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("speak-to-create-schedule")
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
                workTask = Task { await read() }
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

            if requiresReading || !needsReading {
                Text(needsReading
                     ? String(localized: "Liest Name, Symbol und Wiederholung aus dem Satz. Das Gerät wird dabei wärmer, also nur wenn du es möchtest.")
                     : String(localized: "Gelesen. Ändere den Satz, und du kannst ihn neu lesen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func draftSubtitle(_ draft: CreateItemDraft) -> String {
        var parts = [draft.kind == .reminder
                     ? String(localized: "Erinnerung")
                     : String(localized: "Habit")]
        if let minutes = draft.minutes {
            parts.append(String(format: String(localized: "um %02d:%02d"),
                                minutes / 60, minutes % 60))
        } else {
            parts.append(String(localized: "Ganztägig"))
        }
        if let key = draft.schedule.startDay, let date = DayKey.date(from: key, calendar: calendar) {
            let formatted = date.formatted(Date.FormatStyle(date: .long, time: .omitted,
                                                            locale: locale, calendar: calendar,
                                                            timeZone: calendar.timeZone))
            parts.append(draft.schedule.frequency == .once
                         ? formatted : String(format: String(localized: "Ab %@"), formatted))
        }
        if requiresReading {
            parts.append(String(localized: "Wiederholung noch offen"))
        } else if draft.schedule.frequency != .once {
            parts.append(RecurrenceText.pattern(draft.schedule.recurrence, calendar: calendar))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - The floating dock

    @Namespace private var glassNamespace

    /// How much room the dock needs underneath the scrolling content.
    private var dockClearance: CGFloat {
        Theme.Metrics.cardPadding
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
        let ready = draft != nil && draft?.validationMessage == nil
            && !isWorking && !isReading && !didCreate && !dictation.state.isActive
        return Button {
            workTask = Task { await create() }
        } label: {
            HStack(spacing: Theme.Metrics.gap) {
                if isWorking { ProgressView().tint(.white) }
                Text(didCreate
                     ? String(localized: "Angelegt")
                     : requiresReading ? String(localized: "Satz lesen") : String(localized: "Anlegen"))
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
              canRead, isVisible else { return }
        isReading = true
        defer { isReading = false }
        let requestedCalendar = calendar
        let requestedLocale = locale
        let requestedNow = referenceNow
        var result: CreateItemDraft?
        if hasDownloadedModel {
            // The chosen model is on this device, so it is the one that answers.
            switch await localReader.read(requested, locale: requestedLocale,
                                          calendar: requestedCalendar, now: requestedNow) {
            case .draft(let parsed):
                result = parsed
            case .unreadable, .failed:
                // Fall through to Apple's model and then to the deterministic
                // reading, rather than leaving the person with nothing. A model
                // that cannot answer must not be the end of the road.
                break
            }
        }
        if result == nil, !Task.isCancelled, isVisible, text == requested {
            result = await CreateItemDraft.read(from: requested,
                language: requestedLocale.language.languageCode?.identifier ?? "en",
                locale: requestedLocale, calendar: requestedCalendar, now: requestedNow)
        }
        guard !Task.isCancelled, isVisible, text == requested,
              calendar == requestedCalendar, locale == requestedLocale else { return }
        readDraft = result
        readFrom = requested
        expandForReview()
    }

    private func create() async {
        guard let draft, draft.validationMessage == nil, !didCreate,
              !isWorking, !isReading, !dictation.state.isActive, isVisible else { return }
        if requiresReading {
            await read()
            return
        }
        // A sheet left open across midnight needs a fresh visible interpretation.
        if !calendar.isDate(referenceNow, inSameDayAs: .now) {
            referenceNow = Date()
            readDraft = nil
            return
        }
        isWorking = true
        defer { isWorking = false }
        fieldFocused = false
        dictation.cancel()
        switch await CreateItemSaver.save(draft, into: store) {
        case .saved:
            didCreate = true
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        case .emptyName:
            saveError = String(localized: "Der Name fehlt.")
        case .limitReached:
            saveError = CreateItemSaver.limitMessage
        case .failed(let message):
            saveError = message
        case .invalidInput(let message):
            saveError = message
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
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
        isVisible = false
        dictationTask?.cancel()
        dictation.cancel()
        workTask?.cancel()
        dismiss()
    }

    private func toggleDictation() {
        guard !isWorking, !isReading else { return }
        if dictation.state == .listening {
            dictation.stop()
        } else if dictation.state.isActive {
            dictation.cancel()
        } else {
            fieldFocused = false
            expandForReview()
            dictationPrefix = text
            dictation.reset()
            resumeEditingAfterDictation = false
            dictationTask = Task {
                guard !Task.isCancelled, isVisible, !fieldFocused,
                      scenePhase != .background else { return }
                await dictation.start(localeIdentifier: locale.identifier)
            }
        }
    }
}
