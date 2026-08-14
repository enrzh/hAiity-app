import XCTest
@testable import Haiity

/// v18: Schütteln meldet einen Fehler — und die Entwicklerseite gehört ihrem
/// Besitzer.
///
/// Drei Sorten Test, jede aus einem anderen Grund (Muster `DiagnosticsTests`):
///
/// 1. **Reine Logik** an `FeedbackMail`, `ShakeToReport` und
///    `DeveloperAccess.isOwnerDevice` — kein Gerät, kein Mail-Konto, kein
///    Simulator. Derselbe Stand ergibt denselben Text.
/// 2. **Datenschutz.** Was hier verschickt wird, geht endgültig weg. Geprüft
///    wird deshalb, dass das Blatt genau den Bericht anhängt, den
///    `DiagnosticsTests` schon durchleuchtet hat — und keine der Quellen
///    anfasst, an denen Namen liegen.
/// 3. **Quell-Verträge** an dem, was Ansichten TUN statt zurückgeben: die
///    Geste an der Wurzel, die Entprellung, der eine Schalter an zwei Orten,
///    die stumme Tür auf fremden Geräten.
final class FeedbackTests: XCTestCase {

    // MARK: – Der Schalter: reine Logik

    /// **Ab Werk EIN.** `bool(forKey:)` macht aus „noch nie gesetzt" ein
    /// `false` — damit wäre die Meldefunktion für jeden neuen Nutzer
    /// unsichtbar abgeschaltet, und niemand käme je auf die Idee, sie in
    /// „Mehr" zu suchen. Geprüft wird beides: der Anfangszustand und dass ein
    /// bewusstes AUS auch AUS bleibt.
    func testShakeToReportIsOnUntilSomebodyTurnsItOff() {
        let defaults = appGroupDefaults()
        let before = defaults.object(forKey: ShakeToReport.enabledKey)
        defer { restore(before, forKey: ShakeToReport.enabledKey, in: defaults) }

        defaults.removeObject(forKey: ShakeToReport.enabledKey)
        XCTAssertTrue(ShakeToReport.isEnabled, "ein nie berührter Schalter stünde auf aus")

        ShakeToReport.isEnabled = false
        XCTAssertFalse(ShakeToReport.isEnabled)
        ShakeToReport.isEnabled = true
        XCTAssertTrue(ShakeToReport.isEnabled)
    }

    /// Der Schlüssel steht an EINER Stelle. Beide Orte, die ihn umlegen (das
    /// Melde-Blatt und „Mehr"), gehen über `ShakeToReport` — schriebe einer
    /// von beiden selbst in die Defaults, gäbe es zwei Wahrheiten.
    func testBothPlacesWriteTheSameSwitchThroughTheSameDoor() throws {
        XCTAssertEqual(ShakeToReport.enabledKey, "shakeToReport")

        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(sheet.contains("ShakeToReport.isEnabled = false"),
                      "das Blatt kann sich nicht abschalten")
        XCTAssertTrue(more.contains("ShakeToReport.isEnabled = on"),
                      "der Schalter in Mehr schreibt nicht")
        for view in [sheet, more] {
            XCTAssertFalse(view.contains("shakeToReport\""),
                           "eine Ansicht schreibt am gemeinsamen Schlüssel vorbei")
            XCTAssertFalse(view.contains("UserDefaults(suiteName:"),
                           "eine Ansicht greift an der Ablage vorbei in den Topf")
        }
        // Und die Ablage selbst ist die geteilte: der Zustand ist eine
        // Entscheidung über die App, kein Merkmal dieses einen Prozesses.
        let model = try source("Haiity/Models/FeedbackReport.swift")
        XCTAssertTrue(model.contains("UserDefaults(suiteName: SharedStorage.appGroup)"))
    }

    /// **Ein Schlüssel ist noch kein gemeinsamer Blick darauf.**
    ///
    /// Der Schalter in „Mehr" spiegelt den Wert (sonst spränge er beim
    /// Umlegen optisch zurück), und `onAppear` feuert nicht noch einmal, wenn
    /// darüber ein Blatt zufährt: „Mehr" war ja nie weg. Wer also im
    /// Melde-Blatt „nicht mehr fragen" tippt, sähe darunter weiterhin einen
    /// Schalter auf EIN — und sein nächster Tipp darauf schriebe von der
    /// falschen Ausgangslage aus ein zweites AUS. Deshalb ruft die Ablage,
    /// sobald sie sich ändert.
    func testTurningTheSwitchOffAnywhereRefreshesTheOtherPlace() {
        let defaults = appGroupDefaults()
        let before = defaults.object(forKey: ShakeToReport.enabledKey)
        defer { restore(before, forKey: ShakeToReport.enabledKey, in: defaults) }

        var heard = 0
        var seen: [Bool] = []
        let token = NotificationCenter.default.addObserver(
            forName: ShakeToReport.didChange, object: nil, queue: nil) { _ in
                heard += 1
                // Erst ablegen, dann rufen: Wer die Mitteilung hört, muss den
                // NEUEN Wert finden.
                seen.append(ShakeToReport.isEnabled)
            }
        defer { NotificationCenter.default.removeObserver(token) }

        ShakeToReport.isEnabled = false
        ShakeToReport.isEnabled = true
        XCTAssertEqual(heard, 2, "das Umlegen bleibt stumm — der zweite Ort erfährt nichts")
        XCTAssertEqual(seen, [false, true], "die Mitteilung kam vor dem Schreiben")

        // Und der zweite Ort hört wirklich zu.
        let more = try? source("Haiity/Views/MoreView.swift")
        XCTAssertEqual(more?.contains(
            "NotificationCenter.default.publisher(for: ShakeToReport.didChange)"), true,
                       "der Spiegel in Mehr frischt nur beim Erscheinen auf")
    }

    // MARK: – Die Mail: reine Logik

    /// Marke, Version, Build — die Betreffzeile ist das Einzige, was eine
    /// Liste von Meldungen zeigt.
    func testTheSubjectCarriesBrandVersionAndBuild() {
        XCTAssertEqual(FeedbackMail.subject(version: "1.2.3", build: "44"),
                       "hAiity 1.2.3 (44) — Fehlermeldung")
    }

    /// **Der Mensch zuerst.** Was er erlebt hat, steht oben; die Technik
    /// darunter. Ist die Beschreibung leer, entfällt sie SAMT Leerzeile — eine
    /// Mail, die mit zwei leeren Zeilen beginnt, sieht aus wie ein Fehler beim
    /// Verschicken.
    func testTheBodyPutsThePersonFirstAndDropsAnEmptyDescription() {
        let report = "hAiity Diagnose\napp.version: 1.2.3"
        XCTAssertEqual(FeedbackMail.body(description: "Absturz beim Wischen",
                                         diagnostics: report),
                       "Absturz beim Wischen\n\n" + report)
        // Leerraum ist keine Beschreibung.
        XCTAssertEqual(FeedbackMail.body(description: "   \n ", diagnostics: report), report)
        XCTAssertEqual(FeedbackMail.body(description: "", diagnostics: report), report)
        // Und die getippten Ränder wandern nicht mit in die Mail.
        XCTAssertEqual(FeedbackMail.body(description: "  hallo  ", diagnostics: report),
                       "hallo\n\n" + report)
    }

    /// **Es gibt genau ZWEI Wege nach draußen — und keinen dritten auf
    /// Vorrat.** Hier stand einmal ein `mailto:`-Bauer samt zweier
    /// ausführlicher Tests. Aufgerufen hat ihn nie jemand: verschickt wird
    /// über Apples Mail-Fenster, und ohne Mail-Konto über das Teilen-Blatt.
    /// Zwei Tests auf einen Weg, den kein Mensch geht, sind schlimmer als
    /// keine — sie behaupten Prüf-Sicherheit für den Rückfallweg, der
    /// wirklich ausgeliefert wird.
    func testThereIsNoThirdWayOutLyingAround() throws {
        // Geprüft wird der CODE, nicht der Kommentar: der erklärt ja gerade,
        // warum es den dritten Weg NICHT mehr gibt (Muster `ShakeDetector`).
        let model = code(in: try source("Haiity/Models/FeedbackReport.swift"))
        let sheet = code(in: try source("Haiity/Views/FeedbackSheet.swift"))
        for dead in ["mailtoURL", "addingPercentEncoding", "URL(string: \"mailto:"] {
            XCTAssertFalse(model.contains(dead), "toter Weg im Modell: \(dead)")
            XCTAssertFalse(sheet.contains(dead), "toter Weg im Blatt: \(dead)")
        }
        // Und die beiden echten Wege stehen beide da.
        XCTAssertTrue(sheet.contains("MFMailComposeViewController"))
        XCTAssertTrue(sheet.contains("UIActivityViewController"))
    }

    /// Eine Quelldatei ohne ihre Kommentarzeilen — ein Wort im Kommentar ist
    /// kein Aufruf (Muster `ShakeDetector`-Prüfung weiter unten).
    private func code(in swift: String) -> String {
        swift.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Plus-Adressierung auf dieselbe Mailbox — und dieselbe Adresse, die auch
    /// auf der Datenschutzseite steht. Zwei Adressen wären zwei Postfächer,
    /// von denen eines niemand liest.
    func testTheAppAndThePrivacyPageNameTheSameMailbox() throws {
        XCTAssertEqual(FeedbackMail.recipient, "getaiityapp+hAiity@gmail.com")
        for page in ["site/haiity/privacy.html", "site/haiity/en/privacy.html",
                     "site/haiity/index.html", "site/haiity/en/index.html"] {
            let html = try source(page)
            XCTAssertTrue(html.contains(FeedbackMail.recipient),
                          "\(page) nennt eine andere Kontaktadresse")
            XCTAssertFalse(html.contains("leemojix"),
                           "\(page) trägt noch die alte private Adresse")
        }
    }

    // MARK: – Wem die Tür gehört: reine Logik

    /// **Bootstrap.** Solange keine Kennung eingebaut ist, öffnet die Tür wie
    /// bisher — sonst läge der Schlüssel hinter der Tür: die Kennung ist nur
    /// AUF der Entwicklerseite abzulesen.
    func testWithoutABuiltInOwnerEveryDeviceMayOpenTheDoor() {
        XCTAssertNil(DeveloperAccess.ownerAppleUserID,
                     "ist die Kennung eingetragen, gilt der Bootstrap-Zweig nicht mehr")
        // Solange die Konstante leer ist, ist die gespeicherte Kennung
        // GLEICHGÜLTIG — auch die krummen Fälle, die es sonst gar nicht gibt:
        // nicht angemeldet, leer, nur Leerraum, fremde Kennung.
        for stored in [nil, "", "   ", "001234.abcd", "999999.zzzz"] as [String?] {
            XCTAssertTrue(DeveloperAccess.isOwnerDevice(storedAppleUserID: stored),
                          "der Bootstrap-Zweig hält nicht für: \(stored ?? "nil")")
        }
    }

    /// **Die Konstante ist in dieser Runde wirklich leer — und der Vergleich
    /// dahinter kennt kein „ungefähr".** Ein `hasPrefix`, ein `contains` oder
    /// ein `lowercased()` machte aus dem Schloss eine Klinke: eine Kennung,
    /// die zufällig so anfängt oder sich nur in der Schreibweise
    /// unterscheidet, käme durch. Apple vergibt die Kennung als undurchsichtige
    /// Zeichenfolge — an ihr ist nichts zu deuten, nur zu vergleichen.
    func testTheOwnerRuleNeverComparesLoosely() throws {
        let diagnostics = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(diagnostics.contains("static let ownerAppleUserID: String? = nil"),
                      "die Kennung des Besitzers ist noch nicht bekannt — sie steht auf nil")

        // Nur der Vergleichspfad, und darin nur der CODE: die Kommentare
        // erklären ja gerade, warum es das lose Prüfen NICHT gibt.
        let start = try XCTUnwrap(diagnostics.range(of: "static func isOwnerDevice"))
        let end = try XCTUnwrap(diagnostics.range(of: "/// Alles, was der Entwicklerbereich"))
        let code = diagnostics[start.lowerBound..<end.lowerBound]
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        for loose in ["hasPrefix", "hasSuffix", "contains", "lowercased", "uppercased",
                      "caseInsensitive", "localizedStandard", "compare(", "range(of:",
                      "prefix(", "suffix(", "~="] {
            XCTAssertFalse(code.contains(loose), "unscharfer Vergleich im Schloss: \(loose)")
        }
        XCTAssertEqual(code.components(separatedBy: "==").count - 1, 1,
                       "genau EIN Vergleich — jeder weitere ist eine zweite Regel")
    }

    /// **Und wenn sie eingetragen IST, zählt nur exakte Gleichheit.** Das
    /// lässt sich nicht durch Aufrufen prüfen — die Kennung ist eine
    /// eingebaute Konstante, kein Parameter (genau das macht sie zum Schloss
    /// statt zur zweiten Klinke). Geprüft wird deshalb der Quelltext der
    /// Regel: getrimmt, keine gespeicherte Kennung heißt `false`, verglichen
    /// wird mit `==`.
    func testTheOwnerRuleComparesExactlyAndTreatsWhitespaceAsNothing() throws {
        let diagnostics = try source("Haiity/Models/Diagnostics.swift")
        let start = try XCTUnwrap(diagnostics.range(of: "static func isOwnerDevice"))
        let end = try XCTUnwrap(diagnostics.range(of: "/// Alles, was der Entwicklerbereich"))
        let rule = diagnostics[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(rule.contains("guard let owner, !owner.isEmpty else { return true }"),
                      "ohne den Bootstrap-Zweig käme niemand an die Kennung")
        XCTAssertTrue(rule.contains("guard let stored, !stored.isEmpty else { return false }"),
                      "vielleicht der Besitzer ist bei einer Tür keine Antwort")
        XCTAssertTrue(rule.contains("return stored == owner"))
        XCTAssertEqual(rule.components(separatedBy: "trimmingCharacters").count - 1, 2,
                       "Leerraum muss auf BEIDEN Seiten wegfallen")
    }

    /// Die Kennung wohnt neben dem Vornamen, kommt aus demselben Vorgang —
    /// und Leerraum ist keine Kennung.
    func testTheAppleUserIDIsStoredTrimmedAndClearedWhenEmpty() {
        let defaults = appGroupDefaults()
        let before = defaults.object(forKey: PersonalName.appleUserIDKey)
        defer { restore(before, forKey: PersonalName.appleUserIDKey, in: defaults) }

        XCTAssertEqual(PersonalName.appleUserIDKey, "personalAppleUserID")
        PersonalName.appleUserID = "  001234.abcd  "
        XCTAssertEqual(PersonalName.appleUserID, "001234.abcd")
        PersonalName.appleUserID = "   "
        XCTAssertNil(PersonalName.appleUserID, "eine Kennung aus Leerzeichen ist keine")
        PersonalName.appleUserID = "001234.abcd"
        PersonalName.appleUserID = nil
        XCTAssertNil(PersonalName.appleUserID)
    }

    // MARK: – Quell-Verträge: die Geste

    /// **Die System-Geste, kein eigener Schwellwert.** iOS erkennt ein
    /// Schütteln aus dem Verlauf und hat diese Abstimmung auf echten Händen
    /// gemacht. Ein eigener Zähler auf CoreMotion wäre die Wahl zwischen einem
    /// Blatt, das beim Joggen aufspringt, und einem, das erst nach dem dritten
    /// Rütteln kommt — und er kostete dauerhaft Strom.
    func testTheShakeComesFromTheSystemGestureNotFromCoreMotion() throws {
        let detector = try source("Haiity/Views/ShakeDetector.swift")
        XCTAssertTrue(detector.contains("motionEnded(_ motion: UIEvent.EventSubtype"))
        XCTAssertTrue(detector.contains("motion == .motionShake"))
        XCTAssertTrue(detector.contains("extension UIWindow"),
                      "nur das Fenster liegt IMMER in der Antwortkette")
        // Geprüft wird der CODE, nicht der Kommentar — der erklärt ja gerade,
        // warum es den eigenen Bewegungsmesser NICHT gibt.
        let code = detector.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for polling in ["CoreMotion", "CMMotionManager", "accelerometer", "Timer"] {
            XCTAssertFalse(code.contains(polling),
                           "ein eigener Bewegungsmesser: \(polling)")
        }
        // Und der Baustein entscheidet nichts — das tut die Ansicht, der die
        // Blätter gehören.
        XCTAssertFalse(code.contains("ShakeToReport"),
                       "der Melder kennt den Schalter nicht, sonst entscheidet er mit")
        XCTAssertFalse(code.contains("FeedbackSheet"))
    }

    /// **Eine Geste, die niemand benutzt, gehört wieder dem System.**
    ///
    /// Wird aus dem Schütteln ein Blatt, endet die Antwortkette hier — sonst
    /// stünde zusätzlich das System-„Rückgängig?" auf dem Bildschirm. Passiert
    /// dagegen NICHTS (abgeschaltet, es liegt schon etwas oben, die Hand wippt
    /// nach), muss `super` laufen. Ohne diesen Rückweg wäre das
    /// Rückgängig-Schütteln in JEDEM Textfeld der App tot — im Habit-Namen, im
    /// Alias, im Melde-Feld selbst — und wer „Schütteln zum Melden"
    /// ausschaltet, bekäme dafür nicht das Systemverhalten zurück, sondern gar
    /// nichts.
    func testAnUnusedShakeGoesBackToTheSystem() throws {
        let detector = try source("Haiity/Views/ShakeDetector.swift")
        // Zwei Rückwege in die Kette: jede andere Bewegung, und ein Schütteln,
        // das niemand abgeholt hat.
        XCTAssertEqual(detector.components(separatedBy: "super.motionEnded(motion, with: event)")
            .count - 1, 2,
                       "das Schütteln wird immer verschluckt oder immer durchgereicht")
        XCTAssertTrue(detector.contains("guard claim.isClaimed else"),
                      "ohne die Quittung weiß das Fenster nicht, ob jemand die Geste wollte")
        XCTAssertTrue(detector.contains("NotificationCenter.default.post(name: .haiityDeviceDidShake, object: claim)"),
                      "die Quittung muss mit hinausgehen")

        // Und der Rückweg wird auch wirklich abgehakt: `onShake` quittiert
        // NUR, wenn die Ansicht `true` gemeldet hat.
        XCTAssertTrue(detector.contains("func onShake(perform action: @escaping () -> Bool)"))
        XCTAssertTrue(detector.contains("guard action() else { return }"))
        XCTAssertTrue(detector.contains("(note.object as? ShakeClaim)?.claim()"))

        // Die Quittung selbst: einmal abgehakt bleibt abgehakt.
        let claim = ShakeClaim()
        XCTAssertFalse(claim.isClaimed)
        claim.claim()
        XCTAssertTrue(claim.isClaimed)
        claim.claim()
        XCTAssertTrue(claim.isClaimed)
    }

    /// **Ein Schütteln, ein Blatt.** Drei Gründe, aus denen nichts passiert —
    /// abgeschaltet, es ist schon etwas offen, oder es ist noch keine Ruhe
    /// eingekehrt. Fehlte der mittlere, versuchte iOS ein Blatt über einem
    /// Blatt und verschluckte es; fehlte der letzte, käme das eben geschlossene
    /// durch das Nachwippen der Hand sofort zurück.
    func testContentViewOpensTheSheetOnlyWhenNothingElseIsOpen() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains(".onShake { handleShake() }"))
        XCTAssertTrue(content.contains("guard ShakeToReport.isEnabled else { return false }"))
        XCTAssertTrue(content.contains("guard !isPresentingModally else { return false }"))
        XCTAssertTrue(content.contains(
            "guard Date.now.timeIntervalSince(feedbackClosedAt) >= Self.shakeQuietWindow"))
        XCTAssertTrue(content.contains("onDismiss: { feedbackClosedAt = .now }"),
                      "ohne diesen Vermerk beginnt die Ruhezeit nie")
        XCTAssertTrue(content.contains("FeedbackSheet(store: store, cloudStatus: cloudStatus)"))
        // Alle Präsentationen dieser Ansicht an EINER Stelle — ein vergessener
        // Zustand hier ist ein verschlucktes Blatt dort.
        for open in ["showFeedback", "showAdd", "showReminderSetup",
                     "paywall != nil", "editing != nil",
                     "moreSheet != nil", "morePageRoute != nil"] {
            XCTAssertTrue(content.contains(open), "die Blatt-Prüfung kennt \(open) nicht")
        }
        // Zwei Sekunden: so lange braucht eine Hand, um zur Ruhe zu kommen.
        XCTAssertTrue(content.contains("private static let shakeQuietWindow: TimeInterval = 2"))
        // Und die Geste wird nur dann verbraucht, wenn wirklich ein Blatt
        // aufgeht — sonst gehört sie dem System (siehe `ShakeDetector`).
        XCTAssertTrue(content.contains("showFeedback = true\n        return true"),
                      "die Ansicht quittiert die Geste, ohne ein Blatt zu öffnen")
    }

    /// **Die Blatt-Prüfung fragt UIKit, nicht nur sich selbst.**
    ///
    /// Die Wurzel kennt nur ihre EIGENEN Präsentationen. „Mehr" und die
    /// Statistik liegen als Tab-Inhalt darunter und bringen eigene Blätter mit
    /// (Farbe anlegen, Umbenennen, Kaufblatt, Dateiwähler, Teilen). Ein
    /// Schütteln über einem von ihnen setzte sonst `showFeedback = true`,
    /// während iOS gar nichts präsentieren kann — das Blatt wäre verschluckt,
    /// der Zustand bliebe stehen, und ab da wäre die Geste für den Rest der
    /// Sitzung tot.
    func testTheModalCheckAsksUIKitAndNotOnlyItsOwnStates() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains("|| ModalPresentation.isPresenting"),
                      "die Blätter tieferer Ansichten sind für die Prüfung unsichtbar")

        // Und die Frage wird dort gestellt, wo sie IMMER stimmt: am obersten
        // präsentierten Controller des aktiven Fensters.
        let helper = try source("Haiity/Views/ModalPresentation.swift")
        XCTAssertTrue(helper.contains("activeWindow?.rootViewController?.presentedViewController != nil"))
        XCTAssertTrue(helper.contains("while let presented = top.presentedViewController"),
                      "ohne den Aufstieg präsentiert das Teilen-Blatt hinter dem Melde-Blatt")
        XCTAssertTrue(helper.contains("activationState == .foregroundActive"),
                      "im Split View ist das Fenster nicht der Bildschirm")

        // Das Melde-Blatt baut den Aufstieg nicht selbst nach.
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        XCTAssertTrue(sheet.contains("ModalPresentation.topViewController"))
        XCTAssertFalse(sheet.contains("connectedScenes"),
                       "zwei Wege zum obersten Controller sind einer zu viel")
    }

    // MARK: – Quell-Verträge: das Blatt

    /// Die Kennungen, an denen die Simulator-Automatisierung hängt.
    func testTheFeedbackSheetCarriesTheContractIdentifiers() throws {
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        for id in ["\"feedback-description\"", "\"feedback-send\"",
                   "\"feedback-disable-shake\"", "\"feedback-close\""] {
            XCTAssertTrue(sheet.contains(id), "Kennung fehlt: \(id)")
        }
    }

    /// **Niemand verschickt, was er nicht sehen konnte.** Angezeigter und
    /// mitgeschickter Text kommen aus DERSELBEN Quelle — und diese Quelle ist
    /// der Bericht, den `DiagnosticsTests` schon durchleuchtet hat. Und das
    /// Blatt sammelt ihn nicht selbst, sondern über den geteilten Sammler:
    /// zwei Sammellisten liefen auseinander.
    func testTheSheetShowsExactlyWhatItSends() throws {
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        XCTAssertTrue(sheet.contains("facts.map(DiagnosticsReport.text)"),
                      "der angezeigte Text muss der Bericht sein")
        XCTAssertTrue(sheet.contains("FeedbackMail.body(description: text, diagnostics: diagnostics)"),
                      "verschickt werden muss derselbe Text")
        XCTAssertTrue(sheet.contains("await DiagnosticsCollector.local(store: store, cloudStatus: cloudStatus)"))
        XCTAssertFalse(sheet.contains("DiagnosticsFacts()"),
                       "ein eigener Stand neben dem geteilten Sammler")

        // Dieselben Verbote wie auf der Entwicklerseite: das Blatt darf die
        // Quellen, an denen Namen liegen, nicht einmal anfassen.
        for leak in [".name", ".emoji", ".content", "log.values", "Celebration",
                     "PersonalName"] {
            XCTAssertFalse(sheet.contains(leak),
                           "das Melde-Blatt liest \(leak) — das trägt einen Namen")
        }
    }

    /// **Der Knopf tut immer etwas.** Ohne eingerichtetes Mail-Konto ist
    /// `canSendMail()` schlicht `false` — täte „Senden" dann nichts, sähe
    /// ausgerechnet das Blatt kaputt aus, mit dem man Kaputtes meldet.
    func testSendingFallsBackToTheShareSheetInsteadOfDoingNothing() throws {
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        XCTAssertTrue(sheet.contains("guard MFMailComposeViewController.canSendMail() else"))
        XCTAssertTrue(sheet.contains("UIActivityViewController(activityItems: [text]"))
        XCTAssertTrue(sheet.contains("controller.setToRecipients([FeedbackMail.recipient])"))
        // Das Blatt fährt nur nach dem echten Abschicken zu — Abbrechen darf
        // den getippten Text nicht mitnehmen.
        XCTAssertTrue(sheet.contains("onFinish(result == .sent)"))
        XCTAssertTrue(sheet.contains("guard sent else { return }"))
    }

    // MARK: – Quell-Verträge: Mehr und die Tür

    /// Der Schalter steht in „Mehr" — mit erklärendem Fuß, und NICHT zwischen
    /// den beiden Zusammenfassungen: Melden ist keine Erinnerung.
    func testMoreViewCarriesTheShakeSwitchOutsideTheNotificationSections() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("\"shake-to-report-toggle\""))
        XCTAssertTrue(more.contains("shakeToReportSection"))
        let section = try XCTUnwrap(more.range(of: "shakeToReportSection\n"))
        let daily = try XCTUnwrap(more.range(of: "dailySummarySection\n"))
        let weekly = try XCTUnwrap(more.range(of: "weeklySummarySection\n"))
        XCTAssertFalse(daily.upperBound < section.lowerBound
                       && section.upperBound < weekly.lowerBound,
                       "der Schalter steht zwischen den Mitteilungs-Abschnitten")
    }

    /// **Abmelden nimmt die Kennung mit.** Sie kam aus demselben Vorgang wie
    /// der Vorname; bliebe sie liegen, wäre sie der Rest einer Anmeldung, die
    /// der Nutzer gerade zurückgenommen hat.
    func testRemovingTheAppleNameAlsoClearsTheIdentifier() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let remove = try XCTUnwrap(more.range(of: "PersonalName.appleName = nil"))
        let after = more[remove.upperBound...]
        XCTAssertTrue(after.prefix(400).contains("PersonalName.appleUserID = nil"),
                      "der Entfernen-Knopf lässt die Kennung liegen")
        // Und beim Anmelden wird sie IMMER mitgenommen — Apple nennt den
        // Vornamen nur bei der allerersten Anmeldung, die Kennung aber jedes
        // Mal.
        XCTAssertTrue(more.contains("PersonalName.appleUserID = credential.user"))
    }

    /// **Auf fremden Geräten bewegt sich die Tür nicht.** Kein Countdown,
    /// keine Zählung, kein Stups: eine Tür, die sich einen Spalt bewegt,
    /// verrät, dass sie eine ist — und der Countdown wäre die Anleitung gleich
    /// dazu.
    func testTheHiddenDoorOnlyCountsOnTheOwnersDevice() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let tap = try XCTUnwrap(more.range(of: "private func tapVersion()"))
        let next = try XCTUnwrap(more.range(of: "let step = DeveloperAccess.next(taps: taps)"))
        let guardText = more[tap.upperBound..<next.lowerBound]
        XCTAssertTrue(guardText.contains(
            "guard DeveloperAccess.isOwnerDevice(storedAppleUserID: PersonalName.appleUserID)"),
                      "die Prüfung muss VOR der Zählung stehen")
        XCTAssertTrue(guardText.contains("return"))
    }

    /// **Freigeschaltet ist kein Besitztitel.** Die Freischaltung liegt
    /// dauerhaft in den Defaults und überlebt App-Updates. Prüfte nur die
    /// ZÄHLUNG den Besitzer, behielte ein fremdes Gerät, das in dieser
    /// Bootstrap-Runde sieben Mal getippt hat, die Seite für immer — auch in
    /// dem Build, in dem die Kennung des Besitzers eingetragen ist und nicht
    /// zu ihm passt. Gefragt wird deshalb an JEDER Stelle, die zur Seite
    /// führt: an der Zeile in „Über" und an der Seite selbst.
    func testTheDeveloperPageIsGatedByOwnershipAndNotOnlyByTheTapCount() throws {
        // Die Regel selbst: ohne Freischaltung nie, mit Freischaltung nur auf
        // dem Gerät des Besitzers (in dieser Runde: jedes, siehe Bootstrap).
        let before = DeveloperAccess.isUnlocked
        defer { DeveloperAccess.isUnlocked = before }

        DeveloperAccess.isUnlocked = false
        XCTAssertFalse(DeveloperAccess.isAvailable(storedAppleUserID: nil))
        XCTAssertFalse(DeveloperAccess.isAvailable(storedAppleUserID: "001234.abcd"))
        DeveloperAccess.isUnlocked = true
        XCTAssertTrue(DeveloperAccess.isAvailable(storedAppleUserID: "001234.abcd"))

        // Und beide Wege fragen sie — die Zeile UND die Seite.
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("if developerAvailable { developerRow }"))
        XCTAssertTrue(more.contains("developerAvailable = DeveloperAccess.isAvailable("),
                      "die Zeile bleibt stehen, wenn die Kennung später nicht mehr passt")
        XCTAssertFalse(more.contains("= DeveloperAccess.isUnlocked\n"),
                       "die Sichtbarkeit hängt wieder allein an der Freischaltung")

        let content = try source("Haiity/Views/ContentView.swift")
        let route = try XCTUnwrap(content.range(of: "case .developer:"))
        let page = try XCTUnwrap(content.range(of: "DeveloperView(store: store, cloudStatus: cloudStatus)"))
        XCTAssertTrue(content[route.upperBound..<page.lowerBound]
            .contains("DeveloperAccess.isAvailable(storedAppleUserID: PersonalName.appleUserID)"),
                      "die Seite baut sich auf, ohne nach dem Besitzer zu fragen")
    }

    /// **Der Knopf unter „Senden" wirft nichts unbemerkt weg.** „Beim
    /// Schütteln nicht mehr fragen" steht genau dort, wohin der Daumen nach
    /// dem Tippen wandert, und hat zwei unumkehrbare Folgen auf einmal: die
    /// Beschreibung ist weg, die Geste ist abgeschaltet. Steht schon etwas im
    /// Feld, kommt deshalb eine Rückfrage — steht nichts drin, gibt es nichts
    /// zu verlieren und keinen Grund zu fragen.
    func testMutingAsksFirstWhenSomethingWouldBeThrownAway() throws {
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        XCTAssertTrue(sheet.contains("guard hasDescription else"))
        XCTAssertTrue(sheet.contains("asksBeforeMuting = true"))
        XCTAssertTrue(sheet.contains(".confirmationDialog(String(localized: \"Beschreibung verwerfen und nicht mehr fragen?\")"))
        XCTAssertTrue(sheet.contains("\"feedback-disable-shake-confirm\""))
        XCTAssertTrue(sheet.contains("role: .destructive"),
                      "die verwerfende Antwort muss als solche zu erkennen sein")
        XCTAssertTrue(sheet.contains("Button(String(localized: \"Abbrechen\"), role: .cancel) {}"))
        // Und abgeschaltet wird weiterhin an genau EINER Stelle.
        XCTAssertEqual(sheet.components(separatedBy: "ShakeToReport.isEnabled = false").count - 1, 1,
                       "zwei Schreibpunkte für denselben Schalter in einem Blatt")
    }

    /// Die Zeile, ohne die der Schlüssel für immer hinter der Tür läge — samt
    /// ehrlicher Auskunft, wenn niemand angemeldet ist.
    func testTheDeveloperPageShowsAndCopiesTheIdentifier() throws {
        let developer = try source("Haiity/Views/DeveloperView.swift")
        XCTAssertTrue(developer.contains("\"copy-apple-user-id\""))
        XCTAssertTrue(developer.contains("appleUserID = PersonalName.appleUserID"))
        XCTAssertTrue(developer.contains("UIPasteboard.general.string = appleUserID"))
        XCTAssertTrue(developer.contains(#"String(localized: "Nicht angemeldet")"#),
                      "ohne Anmeldung braucht die Zeile eine ehrliche Antwort")
        XCTAssertTrue(developer.contains(".disabled(appleUserID == nil)"),
                      "ein Kopierknopf ohne Inhalt sieht kaputt aus")
    }

    // MARK: – Quell-Verträge: der Katalog

    /// (e) Jeder deutsche Schlüssel des Blatts steht im Katalog — sonst fällt
    /// er auf einem englischen Gerät als deutscher Satz auf, den niemand liest.
    func testEveryFeedbackKeyIsInTheCatalog() throws {
        let strings = try catalog()
        var keys = try localizedKeys(in: source("Haiity/Views/FeedbackSheet.swift"))
        XCTAssertGreaterThan(keys.count, 8, "die Schlüssel-Suche hat fast nichts gefunden")
        // Die drei Schlüssel der anderen beiden Orte dieser Runde.
        keys.formUnion(["Schütteln zum Melden", "Besitzer", "Apple-Kennung dieses Geräts"])
        for key in keys.sorted() {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
    }

    /// (e) **Umgekehrter Vertrag.** Empfänger, Betreff und Rumpf werden NICHT
    /// gelesen, wo sie entstehen, sondern wo sie ankommen — im Postfach der
    /// Entwicklung. Ein auf Urdu betitelter Fehlerbericht beantwortet dort
    /// keine Frage mehr.
    func testTheMailItselfIsNotTranslatable() throws {
        let strings = try catalog()
        for key in [FeedbackMail.recipient,
                    FeedbackMail.subject(version: "1.0.0", build: "44")] {
            XCTAssertNil(strings[key], "die Mail darf nicht übersetzbar sein: \(key)")
        }
        let model = try source("Haiity/Models/FeedbackReport.swift")
        XCTAssertFalse(model.contains("String(localized:"),
                       "in der Mail-Vorlage gibt es nichts zu übersetzen")
    }

    // MARK: – Werkzeug

    private func appGroupDefaults() -> UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    /// Den vorgefundenen Zustand zurücklegen: diese Tests legen echte Schalter
    /// des Test-Hosts um, und der nächste Lauf soll dieselbe Ausgangslage
    /// vorfinden.
    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    private func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["strings"] as? [String: Any])
    }

    /// Alle deutschen Schlüssel einer Quelldatei (Muster `DiagnosticsTests`).
    /// Interpolierte Schlüssel fallen bewusst heraus — sie heißen im Katalog
    /// anders.
    private func localizedKeys(in swift: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: #"String\(localized: "([^"\\]+)"\)"#)
        let range = NSRange(swift.startIndex..., in: swift)
        var keys: Set<String> = []
        for match in regex.matches(in: swift, range: range) {
            guard let found = Range(match.range(at: 1), in: swift) else { continue }
            keys.insert(String(swift[found]))
        }
        return keys
    }
}
