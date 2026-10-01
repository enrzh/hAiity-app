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
        XCTAssertTrue(more.contains("ShakeToReport.isEnabled = enabled"),
                      "der Schalter in Über & Datenschutz schreibt nicht")
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
        XCTAssertTrue(sheet.contains("SFSafariViewController"))
        XCTAssertTrue(sheet.contains("FeedbackIssue.issueURL"))
        XCTAssertFalse(sheet.contains("UIActivityViewController"))
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

    func testOnlyTheBuiltInOwnerIdentityIdentifiesTheDeveloper() {
        XCTAssertEqual(DeveloperAccess.ownerAppleUserID,
                       "000366.5e70aaf77f174436b9c1ad437015d35a.1026")
        XCTAssertEqual(DeveloperAccess.ownerAppleEmail, "xianjie.zhan@icloud.com")
        XCTAssertTrue(DeveloperAccess.isOwnerDevice(
            storedAppleUserID: "000366.5e70aaf77f174436b9c1ad437015d35a.1026",
            storedAppleEmail: nil))
        XCTAssertFalse(DeveloperAccess.isOwnerDevice(
            storedAppleUserID: "000366.5e70aaf77f174436b9c1ad437015d35a.1027",
            storedAppleEmail: nil))
        XCTAssertTrue(DeveloperAccess.isOwnerDevice(
            storedAppleUserID: nil, storedAppleEmail: " xianjie.zhan@icloud.com "))
        XCTAssertTrue(DeveloperAccess.isOwnerDevice(
            storedAppleUserID: nil, storedAppleEmail: "XIANJIE.ZHAN@ICLOUD.COM"))
        for email in [nil, "", "other@icloud.com"] as [String?] {
            XCTAssertFalse(DeveloperAccess.isOwnerDevice(
                storedAppleUserID: nil, storedAppleEmail: email))
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
        XCTAssertTrue(diagnostics.contains(
            "static let ownerAppleUserID: String? = HabitVisibility.ownerAppleUserID"))
        XCTAssertTrue(diagnostics.contains(
            "static let ownerAppleEmail = HabitVisibility.ownerAppleEmail"))

        // Nur der Vergleichspfad, und darin nur der CODE: die Kommentare
        // erklären ja gerade, warum es das lose Prüfen NICHT gibt.
        let start = try XCTUnwrap(diagnostics.range(of: "static func isOwnerDevice"))
        let end = try XCTUnwrap(diagnostics.range(of: "/// Alles, was der Entwicklerbereich"))
        let code = diagnostics[start.lowerBound..<end.lowerBound]
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        for loose in ["hasPrefix", "hasSuffix", "contains", "uppercased",
                      "caseInsensitive", "localizedStandard", "compare(", "range(of:",
                      "prefix(", "suffix(", "~="] {
            XCTAssertFalse(code.contains(loose), "unscharfer Vergleich im Schloss: \(loose)")
        }
    }

    /// **Und wenn sie eingetragen IST, zählt nur exakte Gleichheit.** Das
    /// lässt sich nicht durch Aufrufen prüfen — die Kennung ist eine
    /// eingebaute Konstante, kein Parameter (genau das macht sie zum Schloss
    /// statt zur zweiten Klinke). Geprüft wird deshalb der Quelltext der
    /// Regel: getrimmt, keine gespeicherte Kennung heißt `false`, verglichen
    /// wird mit `==`.
    func testTheOwnerRuleComparesExactlyAndTreatsWhitespaceAsNothing() throws {
        // The rule lives in ONE place now, and this test says so.
        //
        // It used to be sliced out of Diagnostics — where it was a
        // line-for-line copy of the same function in HabitStore. Two
        // implementations meant this assertion could only ever check one of
        // them, and a change to the other would have passed every test in the
        // suite while the two ownership gates disagreed.
        let store = try source("Haiity/Models/HabitStore.swift")
        let start = try XCTUnwrap(store.range(of: "static func isOwnerDevice"))
        let end = try XCTUnwrap(store.range(of: "enum HabitStoreChange"))
        let rule = store[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(rule.contains("storedAppleEmail"))
        XCTAssertTrue(rule.contains("ownerAppleEmail"))
        XCTAssertTrue(rule.contains("lowercased()"), "E-Mail-Adressen sind nicht groß/klein-sensitiv")

        // And the other call chain forwards instead of comparing on its own, so
        // a second copy cannot quietly come back.
        let diagnostics = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(diagnostics.contains("HabitVisibility.isOwnerDevice(storedAppleUserID:"),
                      "der Besitzertest darf an genau einer Stelle vergleichen")
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

    func testTheAppleEmailIsStoredTrimmedAndClearedWhenEmpty() {
        let defaults = appGroupDefaults()
        let before = defaults.object(forKey: PersonalName.appleEmailKey)
        defer { restore(before, forKey: PersonalName.appleEmailKey, in: defaults) }

        XCTAssertEqual(PersonalName.appleEmailKey, "personalAppleEmail")
        PersonalName.appleEmail = "  XIANJIE.ZHAN@ICLOUD.COM  "
        XCTAssertEqual(PersonalName.appleEmail, "xianjie.zhan@icloud.com")
        PersonalName.appleEmail = "   "
        XCTAssertNil(PersonalName.appleEmail)
    }

    func testRepeatAppleLoginRecoversTheVerifiedEmailFromTheIdentityToken() throws {
        let token = try appleIdentityToken(
            email: "XIANJIE.ZHAN@ICLOUD.COM",
            subject: "owner-apple-user",
            audience: "com.aiity.haiity")

        XCTAssertEqual(AppleSignInIdentity.resolvedEmail(
            credentialEmail: nil,
            identityToken: token,
            existingEmail: nil,
            existingUserID: nil,
            userID: "owner-apple-user",
            audience: "com.aiity.haiity"),
            "xianjie.zhan@icloud.com")
    }

    func testRepeatAppleLoginNeverErasesAnExistingVerifiedEmail() {
        XCTAssertEqual(AppleSignInIdentity.resolvedEmail(
            credentialEmail: nil,
            identityToken: nil,
            existingEmail: "xianjie.zhan@icloud.com",
            existingUserID: "owner-apple-user",
            userID: "owner-apple-user",
            audience: "com.aiity.haiity"),
            "xianjie.zhan@icloud.com")

        XCTAssertNil(AppleSignInIdentity.resolvedEmail(
            credentialEmail: nil,
            identityToken: nil,
            existingEmail: "xianjie.zhan@icloud.com",
            existingUserID: "different-apple-user",
            userID: "owner-apple-user",
            audience: "com.aiity.haiity"))
    }

    func testRepeatAppleLoginPreservesTheNameOnlyForTheSameAppleAccount() {
        XCTAssertEqual(AppleSignInIdentity.resolvedName(
            credentialName: nil,
            existingName: " Enrico ",
            existingUserID: "owner-apple-user",
            userID: "owner-apple-user"),
            "Enrico")

        XCTAssertNil(AppleSignInIdentity.resolvedName(
            credentialName: nil,
            existingName: "Enrico",
            existingUserID: "different-apple-user",
            userID: "owner-apple-user"))
    }

    func testAppleSignInPrefillsTheEditableAliasFromANewAppleName() throws {
        let more = try source("Haiity/Views/MoreView.swift")

        XCTAssertTrue(more.contains("let resolvedName = AppleSignInIdentity.resolvedName("))
        XCTAssertTrue(more.contains("let suggestedAlias = AppleSignInIdentity.suggestedAlias("))
        XCTAssertTrue(more.contains("if PersonalName.alias == nil"))
        XCTAssertTrue(more.contains("PersonalName.alias = suggestedAlias"))
        XCTAssertTrue(more.contains("aliasDraft = suggestedAlias"))
        XCTAssertTrue(more.contains("text: aliasBinding"))
        XCTAssertTrue(more.contains("PersonalName.alias = value"))
    }

    func testAppleSignInSuggestsAReadableAliasOnlyFromARealEmail() {
        XCTAssertEqual(AppleSignInIdentity.suggestedAlias(
            resolvedName: nil, email: "xianjie.zhan@icloud.com"),
            "Xianjie Zhan")
        XCTAssertEqual(AppleSignInIdentity.suggestedAlias(
            resolvedName: " Xianjie ", email: "other@icloud.com"),
            "Xianjie")
        XCTAssertNil(AppleSignInIdentity.suggestedAlias(
            resolvedName: nil, email: "random@privaterelay.appleid.com"))
    }

    func testAppleLoginStateOffersLogoutAndRefreshesStoreEntitlements() throws {
        let more = try source("Haiity/Views/MoreView.swift")

        XCTAssertTrue(more.contains("if let storedAppleUserID"))
        XCTAssertTrue(more.contains("accessibilityIdentifier(\"apple-signout\")"))
        XCTAssertTrue(more.contains("Task { await Pro.refresh(mayDowngrade: true) }"))
    }

    func testFloatingToastsUseCompactTypeAndSharedAppearanceSurface() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let components = try source("Haiity/Views/AppUIComponents.swift")

        XCTAssertTrue(content.contains("Text(toast.message)\n                    .font(.footnote)"))
        XCTAssertTrue(content.contains("Text(syncStatus)\n                .font(.footnote)"))
        XCTAssertTrue(content.contains(".appToastSurface()"))
        XCTAssertTrue(components.contains(".appSurface(cornerRadius: 999)"))
    }

    func testNativeToastsUseTheTabViewSafeAreaAndSharedAppearanceSurface() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains(".overlay(alignment: .bottom) { nativeToastOverlay }"),
                      "the toast must be attached to the root shell outside tab content")
        let overlayStart = try XCTUnwrap(content.range(of: "private var nativeToastOverlay"))
        let overlay = content[overlayStart.lowerBound...]
        XCTAssertTrue(overlay.contains("ChromeLayout.toastBottomPadding(nativeBar: true"),
                      "the native toast must use the shared tab-bar clearance contract")
        XCTAssertTrue(overlay.contains(".zIndex(200)"),
                      "the native toast must paint above the tab bar")

        let components = try source("Haiity/Views/AppUIComponents.swift")
        XCTAssertTrue(components.contains("struct AppToastSurface: ViewModifier"))
        XCTAssertTrue(components.contains(".appSurface(cornerRadius: 999)"),
                      "toasts must follow the selected appearance material")
    }

    func testSettingsRowsUseOneSharedLayoutContract() throws {
        let components = try source("Haiity/Views/AppUIComponents.swift")
        let more = try source("Haiity/Views/MoreView.swift")
        let github = try source("Haiity/Views/GitHubSettingsView.swift")
        let reminderSetup = try source("Haiity/Views/ReminderSetupView.swift")

        XCTAssertTrue(components.contains("struct AppSettingsRow<Trailing: View>: View"))
        XCTAssertTrue(components.contains("Theme.Metrics.settingsRowMinHeight"))
        XCTAssertTrue(more.contains("AppSettingsRow(title: title,"))
        XCTAssertTrue(more.contains("AppSettingsRow(title: String(localized: \"GitHub\"),"))
        XCTAssertTrue(github.contains("AppSettingsRow(title: String(localized: \"GitHub-Namen anzeigen\"),"))
        XCTAssertTrue(github.contains("AppSettingsRow(title: String(localized: \"GitHub-Monate anzeigen\"),"))
        XCTAssertTrue(reminderSetup.contains("AppSettingsRow(title: title, detail: text, symbol: symbol)"))
        XCTAssertTrue(reminderSetup.contains("AppSettingsRow(title: String(localized: \"Habit-Erinnerungen\"),"))
        XCTAssertFalse(more.contains("moreIcon("),
                       "More must not keep a second icon-row implementation")
    }

    func testSimulatorCanStageOwnerAndToastOnlyThroughDebugHooks() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let debugStart = try XCTUnwrap(content.range(of: "#if DEBUG\n    /// Nur Debug:"))
        let debugEnd = try XCTUnwrap(content.range(of: "#endif", range: debugStart.upperBound..<content.endIndex))
        let hooks = content[debugStart.lowerBound..<debugEnd.upperBound]

        XCTAssertTrue(hooks.contains("-apple-user-id"))
        XCTAssertTrue(hooks.contains("-show-toast"))
        XCTAssertTrue(hooks.contains("undo.present("))
    }

    func testUnrecognizedAppleAccountCanCopyItsStableIdentifierFromTheAccountSection() throws {
        let more = try source("Haiity/Views/MoreView.swift")

        XCTAssertTrue(more.contains("storedAppleUserID = PersonalName.appleUserID"))
        XCTAssertTrue(more.contains("!DeveloperAccess.isOwnerDevice("))
        XCTAssertTrue(more.contains("UIPasteboard.general.string = storedAppleUserID"))
        XCTAssertTrue(more.contains("accessibilityIdentifier(\"copy-unrecognized-apple-user-id\")"))
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

        // Das Melde-Blatt präsentiert den nativen Safari-Controller als Blatt.
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        XCTAssertTrue(sheet.contains("FeedbackBrowser(url: FeedbackIssue.issueURL)"))
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

    func testFeedbackOpensTheGitHubIssueCreatorInAnInternalBrowser() throws {
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        let model = try source("Haiity/Models/FeedbackReport.swift")

        XCTAssertTrue(sheet.contains("SFSafariViewController"),
                      "Fehler melden must use the native in-app browser")
        XCTAssertTrue(sheet.contains("FeedbackIssue.issueURL"),
                      "the feedback action must use the shared issue destination")
        XCTAssertTrue(model.contains("https://github.com/enrzh/hAiity/issues/new"),
                      "the issue creator URL must point to the hAiity repository")
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
                      "kopiert werden muss derselbe Text")
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

    func testFeedbackUsesTheIssueBrowserAndOffersReportCopying() throws {
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        XCTAssertTrue(sheet.contains("showsGitHubIssues = true"))
        XCTAssertTrue(sheet.contains("UIPasteboard.general.string = reportText"))
        XCTAssertTrue(sheet.contains("\"feedback-copy\""))
        XCTAssertFalse(sheet.contains("UIActivityViewController"))
    }

    // MARK: – Quell-Verträge: Mehr und die Tür

    func testAboutCarriesTheShakeSwitchOutsideNotificationSettings() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("\"shake-to-report-toggle\""))
        let about = try XCTUnwrap(more.range(of: "struct AboutView"))
        let shake = try XCTUnwrap(more.range(of: "\"shake-to-report-toggle\""))
        XCTAssertLessThan(about.lowerBound, shake.lowerBound)
        XCTAssertFalse(more.contains("private var shakeToReportSection"))
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
        XCTAssertTrue(after.prefix(500).contains("PersonalName.appleEmail = nil"),
                      "der Entfernen-Knopf lässt die Besitzer-E-Mail liegen")
        // Und beim Anmelden wird sie IMMER mitgenommen — Apple nennt den
        // Vornamen nur bei der allerersten Anmeldung, die Kennung aber jedes
        // Mal.
        XCTAssertTrue(more.contains("PersonalName.appleUserID = credential.user"))
        XCTAssertTrue(more.contains("identityToken: credential.identityToken"))
        XCTAssertTrue(more.contains("PersonalName.appleEmail = resolvedEmail"))
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
            "guard DeveloperAccess.isOwnerDevice(storedAppleUserID: PersonalName.appleUserID,\n"
            + "                                                  storedAppleEmail: PersonalName.appleEmail)"),
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
        // Das verifizierte Besitzerkonto ist immer Entwickler; der alte
        // versteckte Merker ist dafür nicht mehr Voraussetzung.
        let before = DeveloperAccess.isUnlocked
        defer { DeveloperAccess.isUnlocked = before }

        DeveloperAccess.isUnlocked = false
        XCTAssertTrue(DeveloperAccess.isAvailable(
            storedAppleUserID: nil, storedAppleEmail: "xianjie.zhan@icloud.com"))
        XCTAssertFalse(DeveloperAccess.isAvailable(
            storedAppleUserID: nil, storedAppleEmail: "other@icloud.com"))
        DeveloperAccess.isUnlocked = true
        XCTAssertFalse(DeveloperAccess.isAvailable(
            storedAppleUserID: "001234.abcd", storedAppleEmail: "other@icloud.com"))

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
        let developerRoute = content[route.upperBound..<page.lowerBound]
        XCTAssertTrue(developerRoute.contains(
            "DeveloperAccess.isAvailable(storedAppleUserID: PersonalName.appleUserID,"),
                      "the destination must check the stored Apple identity")
        XCTAssertTrue(developerRoute.contains("storedAppleEmail: PersonalName.appleEmail"),
                      "die Seite baut sich auf, ohne nach dem Besitzer zu fragen")
    }

    func testFeedbackDoesNotShowTheRecipientAddress() throws {
        let sheet = try source("Haiity/Views/FeedbackSheet.swift")
        let start = try XCTUnwrap(sheet.range(of: "private var sendSection"))
        let end = try XCTUnwrap(sheet.range(of: "// MARK: – (4)"))
        XCTAssertFalse(sheet[start.lowerBound..<end.lowerBound].contains("FeedbackMail.recipient"))
        XCTAssertFalse(sheet.contains("Geht an %@."))
    }

    func testMoreKeepsCloudStatusInDeveloperToolsAndUsesConciseSettings() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertFalse(more.contains("iCloudRow"))
        XCTAssertFalse(more.contains("moreCloudRow"))
        XCTAssertFalse(more.contains("icloud-status"))
        let hubStart = try XCTUnwrap(more.range(of: "private var mainSettings: some View"))
        let hubEnd = try XCTUnwrap(more.range(of: "private var accentColor: Color"))
        let hub = more[hubStart.lowerBound..<hubEnd.lowerBound]
        XCTAssertFalse(hub.contains("moreCloudRow"))
        XCTAssertFalse(hub.contains("cloudStatus.state.title"))
        XCTAssertTrue(more.contains("private var cloudSyncSection: some View"),
                      "sync status belongs to the secondary integration settings page")
        XCTAssertTrue(more.contains("cloudStatus.state.title"),
                      "the integration page still needs to explain the current sync state")
        XCTAssertTrue(more.contains("cloud-sync-status"))
        for verbose in ["Verdichtet die Habit-Liste und die untere Navigation dauerhaft.",
                        "Erledigt, +1, Ja und Nein liegen fest auf den Wischgesten.",
                        "Schüttle das iPhone, wenn etwas nicht stimmt:",
                        "Beim Anpassen des App-Icons fragt iOS einmal kurz nach."] {
            XCTAssertFalse(more.contains(verbose), verbose)
        }
        XCTAssertTrue(more.contains("Mitteilungen und Kalender konfigurieren"))
        XCTAssertTrue(more.contains("App-weite Vorgaben und Teilen"))
        XCTAssertFalse(more.contains("moreStatusHero"))
        XCTAssertFalse(more.contains("moreOverview"))
        XCTAssertTrue(try source("Haiity/Views/DeveloperView.swift").contains("cloudSection"))
    }

    func testNotificationSettingsUseIndependentNativeRows() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let start = try XCTUnwrap(more.range(of: "private var notificationSettingsSection: some View"))
        let end = try XCTUnwrap(more.range(of: "private var notificationOptOutRows: some View",
                                           range: start.upperBound..<more.endIndex))
        let section = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(section.contains("AppSettingsGroup"),
                      "notification controls need the shared settings group surface")
        XCTAssertFalse(section.contains("List {"),
                       "a grouped List drops taps on iOS 27, so it must not come back")
        XCTAssertEqual(section.components(separatedBy: "AppSettingsGroup(title:").count - 1, 4,
                       "each notification group needs its own labelled surface")
        XCTAssertEqual(section.components(separatedBy: ".notificationSettingsRow()").count - 1, 4,
                       "each notification group needs its own native hit boundary")
        XCTAssertFalse(section.contains("notificationDivider"),
                       "internal dividers are no longer needed between separate rows")
        let rows = ["notificationOptOutRows", "dailySummaryRows", "weeklySummaryRows", "motivationRows"]
        // `motivationRows` is now followed by the source picker, which used to
        // be preceded by the retired `openSourceMotivationEnabled` binding.
        let nextRows = ["dailySummaryRows", "weeklySummaryRows", "motivationRows",
                        "motivationSourceControl"]
        for (row, nextRow) in zip(rows, nextRows) {
            let rowStart = try XCTUnwrap(more.range(of: "private var \(row): some View"))
            let rowEnd = try XCTUnwrap(more.range(of: "private var \(nextRow):",
                                                  range: rowStart.upperBound..<more.endIndex))
            let rowSource = more[rowStart.lowerBound..<rowEnd.lowerBound]
            XCTAssertTrue(rowSource.contains(".padding(.vertical, Theme.Metrics.gap / 2)"),
                          "\(row) needs the shared vertical breathing room")
        }
    }

    func testWeeklySummaryWeekdayHasItsOwnBoundedMenuTarget() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let start = try XCTUnwrap(more.range(of: "private var weeklySummaryRows: some View"))
        let end = try XCTUnwrap(more.range(of: "private var motivationRows: some View",
                                           range: start.upperBound..<more.endIndex))
        let rows = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(rows.contains("weeklyWeekdayButton"),
                      "the weekday choice must be an explicitly bounded control")
        XCTAssertFalse(rows.contains("Picker(String(localized: \"Wochentag\")"),
                       "the default Picker can claim the entire notification row")
        XCTAssertFalse(more.contains("private var weeklyWeekdayMenu: some View"),
                       "the flexible Menu label can claim the surrounding glass group")
        XCTAssertTrue(more.contains("private var weeklyWeekdayButton: some View"))
        XCTAssertTrue(more.contains(".fixedSize(horizontal: true, vertical: false)"),
                      "the weekday button must keep an intrinsic hit target")
        XCTAssertTrue(more.contains("showWeeklyWeekdayPicker"),
                      "weekday choices should be presented independently from the list row")
    }

    /// The source control used to be a link out to a quote repository, and the
    /// hazard this test guarded was real: a `Button` inside a settings row can
    /// inherit the whole row on iOS 27 and steal taps from its neighbours. The
    /// link is gone, and the replacement is a segmented `Picker` plus a caption.
    /// What must survive is the shape — a bounded native control, never a
    /// row-wide gesture, and never a caption that claims the row.
    func testTheMotivationSourceControlStaysABoundedNativeControl() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let start = try XCTUnwrap(more.range(of: "private var motivationRows: some View"))
        let end = try XCTUnwrap(more.range(of: "private var motivationSourceControl: some View",
                                           range: start.upperBound..<more.endIndex))
        let rows = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(rows.contains("motivationSourceControl"),
                      "the source picker must be referenced from the motivation rows")
        let control = more[end.lowerBound..<more.endIndex]
        XCTAssertTrue(control.contains(".pickerStyle(.segmented)"),
                      "a segmented picker is a bounded native control")
        XCTAssertTrue(control.contains("accessibilityIdentifier(\"motivation-source-picker\")"),
                      "the control needs its own identifier for UI tests")
        XCTAssertFalse(control.contains(".onTapGesture"),
                       "a gesture on the caption can expand across the row")
        XCTAssertFalse(more.contains("openMotivationSource"),
                       "the retired repository link must not come back")
    }

    func testBehaviorAndDeveloperCategoriesUseOneMaterialRow() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let developer = try source("Haiity/Views/DeveloperView.swift")

        func categoryBody(_ source: String, _ marker: String, _ nextDeclaration: String) throws -> String {
            let start = try XCTUnwrap(source.range(of: "private var \(marker): some View"))
            let end = try XCTUnwrap(source.range(of: nextDeclaration,
                                                range: start.upperBound..<source.endIndex))
            return String(source[start.lowerBound..<end.lowerBound])
        }

        // Both pages moved off `List` to the shared group surface, because iOS
        // 27 drops taps on grouped list rows. One group, one material row.
        for (category, next) in [("autoArchiveSection", "private var compactModeSection: some View"),
                                 ("swipeActionsSection", "private var notificationActionsSection: some View"),
                                 ("notificationActionsSection", "private func notificationSlotTitle"),
                                 ("calendarSection", "private func cleanupNativeEntries")] {
            let body = try categoryBody(more, category, next)
            XCTAssertTrue(body.contains("AppSettingsGroup(title:"), category)
        }

        let developerCategories = [("appSection", "private var dataSection: some View"),
                                   ("dataSection", "private var fileSize"),
                                   ("cloudSection", "private var notificationSection: some View"),
                                   ("notificationSection", "private var testNotificationButton: some View"),
                                   ("calendarSection", "private var proSection: some View"),
                                   ("proSection", "private var dataTransferSection: some View"),
                                   ("dataTransferSection", "private var actionSection: some View"),
                                   ("actionSection", "private var ownerSection: some View"),
                                   ("ownerSection", "private func handleImport")]
        for (category, next) in developerCategories {
            let body = try categoryBody(developer, category, next)
            XCTAssertTrue(body.contains("AppSettingsGroup(title:"), category)
        }
        XCTAssertFalse(more.contains("moreSettingsSection()"),
                       "the More settings pages must not go back to a List-backed section")
        XCTAssertFalse(developer.contains("moreSettingsSection()"),
                       "the developer page must not go back to a List-backed section")
    }

    func testOwnerDeveloperAccessHasNoNonWorkingHideControl() throws {
        let developer = try source("Haiity/Views/DeveloperView.swift")
        XCTAssertFalse(developer.contains("lockSection"))
        XCTAssertFalse(developer.contains("DeveloperAccess.isUnlocked = false"))
    }

    func testMoreUsesRequestedPageOrderAndDedicatedSettingsScreens() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        for route in ["case archive, about, developer, appearance, habitBehavior, github",
                      "case .appearance:", "case .habitBehavior:",
                      "Darstellung", "Verhalten & Teilen"] {
            XCTAssertTrue(more.contains(route), route)
        }

        let body = try XCTUnwrap(more.range(of: "private var mainSettings: some View"))
        let end = try XCTUnwrap(more.range(of: "private var appearanceSettings: some View"))
        let main = more[body.lowerBound..<end.lowerBound]
        // Grouped by intent, not taxonomy: Alltag, then Konto & Verbindungen,
        // then Archiv & Über. The order inside the hub is the contract.
        let ordered = ["MoreRoute.appearance",
                       "showingNotificationSettings", "MoreRoute.habitBehavior",
                       "moreGitHubRow", "showingPersonalSettings",
                       "showReminderSetup", "pageRow(.archive", "pageRow(.about", "proSection"]
        var cursor = main.startIndex
        for marker in ordered {
            let range = try XCTUnwrap(main.range(of: marker, range: cursor..<main.endIndex), marker)
            cursor = range.upperBound
        }
        XCTAssertTrue(main.contains("AppSettingsGroup"),
                      "the rebuilt More page must keep each group in its own surface")

        let appearanceStart = try XCTUnwrap(
            more.range(of: "private var appearanceSettings: some View"))
        let behaviorStart = try XCTUnwrap(
            more.range(of: "private var habitBehaviorSettings: some View"))
        let appearance = more[appearanceStart.lowerBound..<behaviorStart.lowerBound]
        XCTAssertTrue(appearance.contains("compactModeSection"))
        let behavior = more[behaviorStart.lowerBound...]
        XCTAssertFalse(behavior.prefix(250).contains("compactModeSection"))
    }

    func testDynamicAppIconLabelExplainsAndHidesManualChoices() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("App-Icon dynamisch"))
        XCTAssertTrue(more.contains("Gleiche Farbe wie Graph-Farbe."))
        XCTAssertTrue(more.contains("if !store.matchAppIcon"))
        XCTAssertFalse(more.contains("App-Icon anpassen"))
    }

    func testMovedSettingsHaveOneVisibleHome() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let developer = try source("Haiity/Views/DeveloperView.swift")
        XCTAssertTrue(more.contains("AboutView"))
        XCTAssertTrue(more.contains("shake-to-report-toggle"))
        XCTAssertFalse(more.contains("private var shakeToReportSection"))
        XCTAssertTrue(developer.contains("export-data"))
        XCTAssertTrue(developer.contains("import-data"))
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

    private func appleIdentityToken(email: String,
                                    subject: String,
                                    audience: String) throws -> Data {
        let payload: [String: Any] = [
            "iss": "https://appleid.apple.com",
            "aud": audience,
            "sub": subject,
            "email": email,
            "email_verified": true
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let encoded = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Data("header.\(encoded).signature".utf8)
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
