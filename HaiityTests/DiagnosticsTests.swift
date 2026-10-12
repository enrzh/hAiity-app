import XCTest
@testable import Haiity

/// v17: die versteckte Tür, der Entwicklerbereich und der kopierbare
/// Diagnosetext.
///
/// Drei Sorten Test in einer Datei, jede aus einem anderen Grund:
///
/// 1. **Reine Logik** an `DeveloperAccess` und `DiagnosticsReport` — kein
///    Bundle, kein Gerät, keine Uhr. Genau dafür wurden Zählung und Bericht
///    von der Ansicht getrennt.
/// 2. **Datenschutz.** Der Bericht landet per Zwischenablage in fremden
///    Händen: in einer Mail, einem Forum, einem Ticket. Geprüft wird deshalb
///    nicht „wir schreiben keine Namen raus", sondern dass es GAR KEIN Feld
///    gibt, das einen Namen tragen könnte — und dass die Ansicht die Quellen,
///    an denen Namen liegen (Habit, Alias, Mitteilungstext), nicht einmal
///    anfasst.
/// 3. **Quell-Verträge** (Muster `ProGateTests`) an dem, was eine Ansicht tut
///    statt zurückgibt: die Tür in „Über", die Kennungen der Seite, und die
///    Abwesenheit einer Debug-Klammer. Ein `#if DEBUG` um diese Seite fiele
///    in keinem Simulator auf — es fehlte erst dort, wo die Seite gebraucht
///    wird: im Release-Build auf einem fremden Gerät.
final class DiagnosticsTests: XCTestCase {

    // MARK: – Die versteckte Tür: reine Logik

    /// Sieben ist eine Absprache mit der Anleitung am Telefon („tipp
    /// siebenmal auf die Version"). Der Countdown beginnt später, sonst wäre
    /// die Tür schon beim ersten Tipp verraten.
    func testTheDoorNeedsSevenTapsAndStaysHiddenForThree() {
        XCTAssertEqual(DeveloperAccess.tapsRequired, 7)
        XCTAssertEqual(DeveloperAccess.hintStartsAtTap, 4)
        XCTAssertLessThan(DeveloperAccess.hintStartsAtTap, DeveloperAccess.tapsRequired,
                          "ein Countdown, der erst nach dem Aufschließen anfinge, wäre keiner")
    }

    /// Die ganze Treppe: sechs Tipps zählen nur hoch, der siebte schließt auf.
    /// Ein Zaunpfahl-Fehler hier ist entweder eine Tür, die zu früh aufgeht
    /// (dann ist sie nicht mehr versteckt), oder eine, die man nicht
    /// aufbekommt.
    func testEveryTapCountsUpAndOnlyTheSeventhUnlocks() {
        for taps in 0..<(DeveloperAccess.tapsRequired - 1) {
            let step = DeveloperAccess.next(taps: taps)
            XCTAssertEqual(step.taps, taps + 1)
            XCTAssertFalse(step.unlocked,
                           "Tipp \(taps + 1) von \(DeveloperAccess.tapsRequired) hat schon aufgeschlossen")
        }
        let last = DeveloperAccess.next(taps: DeveloperAccess.tapsRequired - 1)
        XCTAssertTrue(last.unlocked, "der siebte Tipp muss aufschließen")
    }

    /// **Der Zähler fällt beim Aufschließen auf 0 zurück.** Bliebe er stehen,
    /// wäre nach „Entwicklerbereich ausblenden" ein einziger Tipp genug — die
    /// versteckte Tür stünde ab dem ersten Mal für immer angelehnt.
    func testUnlockingResetsTheCounterSoHidingAgainMeansSomething() {
        let unlock = DeveloperAccess.next(taps: DeveloperAccess.tapsRequired - 1)
        XCTAssertTrue(unlock.unlocked)
        XCTAssertEqual(unlock.taps, 0, "nach dem Ausblenden würde sonst ein Tipp genügen")
    }

    /// Unsinnige Eingaben können nur aus Fehlgebrauch kommen — trotzdem darf
    /// weder eine negative Zahl noch ein davongelaufener Zähler die Treppe
    /// zerlegen.
    func testNextClampsNonsenseInsteadOfBreaking() {
        let negative = DeveloperAccess.next(taps: -3)
        XCTAssertEqual(negative.taps, 1)
        XCTAssertFalse(negative.unlocked)

        let beyond = DeveloperAccess.next(taps: 99)
        XCTAssertTrue(beyond.unlocked)
        XCTAssertEqual(beyond.taps, 0)
    }

    /// Vorher stumm, nachher wieder stumm: „Noch 0 Tipps" wäre eine Lüge über
    /// einen Zustand, der schon eingetreten ist.
    func testHintIsSilentBeforeTheFourthTapAndAfterTheDoorIsOpen() {
        for taps in [-1, 0, 1, 2, 3] {
            XCTAssertNil(DeveloperAccess.hint(for: taps),
                         "bei \(taps) Tipps verrät sich die versteckte Tür")
        }
        for taps in DeveloperAccess.hintStartsAtTap..<DeveloperAccess.tapsRequired {
            let hint = DeveloperAccess.hint(for: taps)
            XCTAssertNotNil(hint, "ab dem vierten Tipp muss der Countdown mitlaufen (\(taps))")
            XCTAssertFalse(hint?.isEmpty ?? true, "leerer Hinweis bei \(taps) Tipps")
        }
        XCTAssertNil(DeveloperAccess.hint(for: DeveloperAccess.tapsRequired))
        XCTAssertNil(DeveloperAccess.hint(for: 12))
    }

    /// **Sprachunabhängig geprüft.** Die Einzahl beim letzten Tipp ist ein
    /// eigener Schlüssel, also ein anderer Text als die Mehrzahl — welcher,
    /// hängt an der Sprache des Geräts und ist hier nicht die Frage. Dass die
    /// Verzweigung existiert, nagelt zusätzlich der Quell-Vertrag fest
    /// (`testTheHintKeysAreGermanAndTypographic`).
    func testTheLastTapReadsDifferentlyFromTheOnesBefore() throws {
        let three = try XCTUnwrap(DeveloperAccess.hint(for: 4))
        let two = try XCTUnwrap(DeveloperAccess.hint(for: 5))
        let one = try XCTUnwrap(DeveloperAccess.hint(for: 6))
        XCTAssertNotEqual(one, two, "der letzte Tipp braucht die Einzahl")
        XCTAssertNotEqual(two, three, "der Countdown muss die Restzahl nennen")
    }

    /// **Die Freischaltung ist app-lokal.** Sie ist eine Aussage über DIESES
    /// Gerät und DIESE App: das Widget braucht sie nicht, iCloud soll sie
    /// nicht spiegeln, und in der App-Group läge sie im selben Topf wie Kauf-
    /// und Kalender-Zustand — dort wäre sie später schwer wieder loszuwerden.
    func testTheUnlockFlagLivesInTheAppNotInTheAppGroup() {
        XCTAssertEqual(DeveloperAccess.unlockedKey, "developerUnlocked")

        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: DeveloperAccess.unlockedKey) as? Bool
        defer {
            if let original {
                defaults.set(original, forKey: DeveloperAccess.unlockedKey)
            } else {
                defaults.removeObject(forKey: DeveloperAccess.unlockedKey)
            }
        }

        DeveloperAccess.isUnlocked = true
        XCTAssertTrue(DeveloperAccess.isUnlocked)
        XCTAssertTrue(defaults.bool(forKey: DeveloperAccess.unlockedKey))
        XCTAssertNil(UserDefaults(suiteName: SharedStorage.appGroup)?
            .object(forKey: DeveloperAccess.unlockedKey),
                     "die Freischaltung darf nicht in der App-Group landen")

        DeveloperAccess.isUnlocked = false
        XCTAssertFalse(DeveloperAccess.isUnlocked)
    }

    // MARK: – Der Bericht: Inhalt und Reihenfolge

    /// **Der ganze Bericht auf einmal.** Zwei Meldungen desselben Fehlers
    /// sollen sich untereinander legen lassen — deshalb steht hier der
    /// vollständige erwartete Text und nicht eine Handvoll `contains`. Eine
    /// verschobene, umbenannte oder zusätzliche Zeile fällt so sofort auf.
    func testTheReportRendersEveryFactInAFixedOrder() {
        let expected = """
        hAiity Diagnose
        report.collected: 2026-08-14T18:41:00Z
        app.version: 1.2.3
        app.build: 44
        app.bundle: com.aiity.haiity
        app.configuration: Release
        app.ios: 26.4.1
        app.device: iPhone18,2
        data.habits.active: 7
        data.habits.archived: 2
        data.log.entries: 1234
        data.log.oldest: 2024-01-31
        data.file.bytes: 692
        data.file.modified: 2026-08-14T18:41:00Z
        data.appgroup: 28A6DD4E-1E1F-4C6E-9A2B-0F5D3C7A11B9
        cloud.status: active 2026-08-14T18:41:00Z
        notifications.authorization: authorized
        notifications.pending: 9
        notifications.next.1: summary 2026-08-15T06:00:00Z
        notifications.next.2: summary-weekly 2026-08-16T18:00:00Z
        calendar.enabled: true
        calendar.title: hAiity
        calendar.events: 12
        pro.unlocked: true
        pro.product: com.aiity.haiity.pro
        pro.price: 4,99 €
        """
        XCTAssertEqual(DiagnosticsReport.text(filledFacts()), expected)
    }

    /// Derselbe Stand, zweimal gefragt: derselbe Text. Ein Bericht, der bei
    /// jedem Aufruf anders aussieht (Wörterbuch-Reihenfolge, Ortszeit), ist
    /// als Vergleichsgrundlage wertlos.
    func testTheReportIsStableAcrossCalls() {
        let facts = filledFacts()
        XCTAssertEqual(DiagnosticsReport.text(facts), DiagnosticsReport.text(facts))
        XCTAssertEqual(DiagnosticsReport.text(DiagnosticsFacts()),
                       DiagnosticsReport.text(DiagnosticsFacts()))
    }

    /// **Jede Zeile kommt immer.** Ein fehlender Wert ist selbst ein Befund —
    /// „die Zeile war gar nicht da" und „die Zeile sagte n/a" sind zwei sehr
    /// verschiedene Auskünfte.
    func testEveryLineSurvivesAMissingValue() {
        let lines = DiagnosticsReport.text(DiagnosticsFacts()).components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "hAiity Diagnose")
        XCTAssertEqual(lines.count, Self.reportKeys.count + 1,
                       "der leere Bericht hat Zeilen verloren oder erfunden")
        for key in Self.reportKeys {
            XCTAssertTrue(lines.contains { $0.hasPrefix("\(key): ") },
                          "Zeile fehlt im leeren Bericht: \(key)")
        }
        for optional in ["report.collected", "data.log.oldest", "data.file.bytes",
                         "data.file.modified", "data.appgroup", "notifications.next",
                         "calendar.title", "pro.price"] {
            XCTAssertTrue(lines.contains("\(optional): \(DiagnosticsReport.unknown)"),
                          "\(optional) meldet keinen fehlenden Wert")
        }
    }

    /// **Eine Null ist eine Zahl, kein fehlender Wert.** „0 geplante
    /// Mitteilungen" beantwortet eine Frage; `n/a` an derselben Stelle
    /// beantwortet sie nicht.
    func testZeroIsReportedAsANumberAndNotAsMissing() {
        let lines = DiagnosticsReport.text(DiagnosticsFacts()).components(separatedBy: "\n")
        for key in ["data.habits.active", "data.habits.archived", "data.log.entries",
                    "notifications.pending", "calendar.events"] {
            XCTAssertTrue(lines.contains("\(key): 0"), "\(key) meldet eine 0 als n/a")
        }
        XCTAssertTrue(lines.contains("calendar.enabled: false"))
        XCTAssertTrue(lines.contains("pro.unlocked: false"))
    }

    /// Der Bericht geht in eine Zwischenablage, nicht in ein Protokoll:
    /// hundert Zeilen Wecker wären die Nadel im eigenen Heuhaufen. Ohne
    /// Wecker steht dort genau EINE Zeile — sonst verschwände der Abschnitt.
    func testAtMostFiveUpcomingNotificationsAndOneLineWhenThereAreNone() {
        XCTAssertEqual(DiagnosticsReport.maxNextNotifications, 5)

        var many = DiagnosticsFacts()
        many.nextNotifications = (1...9).map {
            (id: "habit-reminder-\($0)", date: date("2026-08-1\($0 % 9)T07:00:00Z"))
        }
        let lines = DiagnosticsReport.text(many).components(separatedBy: "\n")
        let numbered = lines.filter { $0.hasPrefix("notifications.next.") }
        XCTAssertEqual(numbered.count, DiagnosticsReport.maxNextNotifications)
        for index in 1...DiagnosticsReport.maxNextNotifications {
            XCTAssertTrue(lines.contains { $0.hasPrefix("notifications.next.\(index): ") },
                          "die Nummerierung hat eine Lücke bei \(index)")
        }
        XCTAssertFalse(lines.contains { $0.hasPrefix("notifications.next: ") },
                       "die Sammelzeile darf neben aufgeführten Weckern nicht stehen")

        let empty = DiagnosticsReport.text(DiagnosticsFacts()).components(separatedBy: "\n")
        XCTAssertEqual(empty.filter { $0.hasPrefix("notifications.next") },
                       ["notifications.next: \(DiagnosticsReport.unknown)"])
    }

    /// **Ein Wert darf die Reihenfolge nicht sprengen.** Der iCloud-Zustand
    /// bringt einen ganzen Satz mit; ein Zeilenumbruch mittendrin würde die
    /// feste Reihenfolge zerlegen, an der sich zwei Meldungen vergleichen.
    func testValuesAreFlattenedToASingleLine() {
        var facts = DiagnosticsFacts()
        facts.cloudStatus = "failed: Der Container\nwar nicht erreichbar\n"
        let lines = DiagnosticsReport.text(facts).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, Self.reportKeys.count + 1,
                       "ein mehrzeiliger Wert hat den Bericht aufgebläht")
        XCTAssertTrue(lines.contains("cloud.status: failed: Der Container war nicht erreichbar"))
    }

    /// UTC und ISO-8601: Der Zeitstempel wird woanders gelesen als dort, wo er
    /// entstand — mit der Zeitzone des Absenders wäre er nur ein Rätsel.
    func testTimestampsAreIsoUtc() {
        XCTAssertEqual(DiagnosticsReport.timestamp(date("2026-08-14T18:00:00Z")),
                       "2026-08-14T18:00:00Z")
        XCTAssertEqual(DiagnosticsReport.timestamp(Date(timeIntervalSince1970: 0)),
                       "1970-01-01T00:00:00Z")
        XCTAssertTrue(DiagnosticsReport.timestamp(Date()).hasSuffix("Z"),
                      "ohne Z ist der Zeitstempel eine Ortszeit ohne Ort")
    }

    /// **Der Bericht spricht keine Sprache.** Er wird nicht gelesen, wo er
    /// entsteht, sondern wo er ankommt. Eine auf Urdu übersetzte Diagnose
    /// beantwortet dort keine Frage mehr — die Schlüssel bleiben ASCII, und
    /// zwar unabhängig davon, in welcher Sprache dieser Testlauf läuft.
    func testTheReportKeysStayAsciiAndUntranslated() {
        let lines = DiagnosticsReport.text(filledFacts()).components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "hAiity Diagnose")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        for line in lines.dropFirst() {
            let separator = line.range(of: ": ")
            XCTAssertNotNil(separator, "Zeile ohne Schlüssel: \(line)")
            guard let separator else { continue }
            let key = String(line[line.startIndex..<separator.lowerBound])
            XCTAssertFalse(key.isEmpty)
            XCTAssertTrue(key.unicodeScalars.allSatisfy { allowed.contains($0) },
                          "übersetzter oder verzierter Schlüssel: \(key)")
        }
    }

    // MARK: – Datenschutz

    /// **Die Struktur IST die Regel.** Ein Test, der nur nachsähe, ob im Text
    /// gerade kein Name steht, ginge beim nächsten Feld wieder auf. Deshalb
    /// steht hier die vollständige Feldliste: Wer `habitNames`, `alias` oder
    /// `logValues` hinzufügt, muss diesen Test ändern — und dabei über den
    /// Bug-Report nachdenken, der in fremden Händen landet.
    func testFactsHaveNoFieldThatCouldEverCarryAName() {
        let labels = Mirror(reflecting: DiagnosticsFacts()).children.compactMap(\.label)
        XCTAssertEqual(labels, [
            "collectedAt",
            "appVersion", "build", "bundleID", "configuration", "systemVersion", "deviceModel",
            "activeHabits", "archivedHabits", "logEntries", "oldestLogDay",
            "dataFileBytes", "dataFileModified", "appGroupContainer",
            "cloudStatus",
            "notificationAuthorization", "pendingNotifications", "nextNotifications",
            "calendarEnabled", "calendarTitle", "calendarEvents",
            "proUnlocked", "proProductID", "proPrice",
        ], "die Feldliste hat sich geändert — was kann das neue Feld verraten?")

        // Und kein Feld trägt einen Habit mit sich herum: dann käme der Name
        // über die Hintertür doch wieder an.
        for child in Mirror(reflecting: filledFacts()).children {
            let type = String(describing: type(of: child.value))
            XCTAssertFalse(type.contains("Habit"),
                           "\(child.label ?? "?") trägt \(type) — darin steckt der Name")
        }
    }

    /// **Der Bericht sagt nichts, was ihm nicht gegeben wurde.** Jeder Wert im
    /// Text muss aus einem Feld stammen, das dieser Test gefüllt hat. Fasst
    /// jemand später aus dem Bericht heraus nach einer globalen Quelle
    /// (`PersonalName.effective`, ein Habit, ein Log-Wert), steht dort ein
    /// Wert, den niemand hineingegeben hat — und genau das schlägt hier fehl.
    func testTheReportSaysNothingItWasNotGiven() {
        let fed: Set<String> = [
            "1.2.3", "44", "com.aiity.haiity", "Release", "26.4.1", "iPhone18,2",
            "7", "2", "1234", "2024-01-31", "692", "2026-08-14T18:41:00Z",
            "28A6DD4E-1E1F-4C6E-9A2B-0F5D3C7A11B9",
            "active 2026-08-14T18:41:00Z", "authorized", "9",
            "summary 2026-08-15T06:00:00Z", "summary-weekly 2026-08-16T18:00:00Z",
            "true", "hAiity", "12", "com.aiity.haiity.pro", "4,99 €",
            DiagnosticsReport.unknown,
        ]
        let lines = DiagnosticsReport.text(filledFacts()).components(separatedBy: "\n").dropFirst()
        for line in lines {
            guard let separator = line.range(of: ": ") else {
                XCTFail("Zeile ohne Schlüssel: \(line)")
                continue
            }
            let value = String(line[separator.upperBound...])
            XCTAssertTrue(fed.contains(value), "Wert im Bericht, den niemand gab: \(line)")
        }
    }

    /// **Der Kalendertitel ist der einzige Wert, den ein Mensch tippen kann —
    /// und er geht nicht roh hinaus.** iOS lässt jeden Kalender in der
    /// Kalender-App umbenennen. Aus „hAiity" wird dann „Enricos Gewohnheiten
    /// 🌱": ein Name und ein Zeichen, also genau das, was dieser Bericht laut
    /// seinem eigenen Versprechen nicht trägt. Die Auskunft bleibt trotzdem
    /// vollständig — gefragt ist nie, WIE er heisst, sondern ob es noch der
    /// von hAiity angelegte ist.
    func testTheCalendarTitleNeverLeavesTheDeviceAsFreeText() {
        XCTAssertEqual(DiagnosticsReport.calendarTitleToken(CalendarSync.calendarTitle),
                       CalendarSync.calendarTitle, "der unveränderte Kalender ist eine Auskunft")
        XCTAssertEqual(DiagnosticsReport.calendarTitleToken(CalendarSync.habitsCalendarTitle),
                       CalendarSync.habitsCalendarTitle, "der Habits-Kalender ist eine Auskunft")
        XCTAssertEqual(DiagnosticsReport.calendarTitleToken(CalendarSync.remindersCalendarTitle),
                       CalendarSync.remindersCalendarTitle, "der Erinnerungen-Kalender ist eine Auskunft")
        XCTAssertEqual(DiagnosticsReport.calendarTitleToken("  hAiity  "),
                       CalendarSync.calendarTitle, "Leerraum ist keine Umbenennung")
        for renamed in ["Enricos Gewohnheiten 🌱", "hAiity (alt)", "HAIITY", "Gewohnheiten"] {
            XCTAssertEqual(DiagnosticsReport.calendarTitleToken(renamed), "renamed",
                           "der getippte Name geht mit hinaus: \(renamed)")
        }
        // Kein Kalender bleibt kein Kalender: `n/a` ist die dritte Antwort.
        XCTAssertNil(DiagnosticsReport.calendarTitleToken(nil))
        XCTAssertNil(DiagnosticsReport.calendarTitleToken("   "))

        var facts = DiagnosticsFacts()
        facts.calendarTitle = "Enricos Gewohnheiten 🌱"
        let report = DiagnosticsReport.text(facts)
        XCTAssertTrue(report.contains("calendar.title: renamed"))
        XCTAssertFalse(report.contains("Enricos"), "der Name steht im Bericht")
        XCTAssertFalse(report.contains("🌱"), "das Zeichen steht im Bericht")
    }

    func testDiagnosticsRecognizesEitherNewCalendarTitle() throws {
        let source = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(source.contains("CalendarSync.activeCalendarTitle"))
        XCTAssertTrue(source.contains("CalendarSync.habitsCalendarTitle"))
        XCTAssertTrue(source.contains("CalendarSync.remindersCalendarTitle"))
    }

    /// **Aus dem App-Group-Pfad kommt nur sein letzter Teil.** Auf dem iPhone
    /// ist der ganze Pfad harmlos — im Simulator und unter „iPhone Apps on
    /// Mac" beginnt derselbe Pfad aber im HEIMATVERZEICHNIS, und der Kurzname
    /// eines Mac-Kontos ist regelmäßig der Vorname eines Menschen. Der
    /// Bericht verspricht „nur Zahlen, Zustände und technische Kennungen";
    /// dieses Versprechen hält nur der letzte Teil — und er beantwortet
    /// dieselbe Frage: welcher Container, und gibt es ihn.
    func testTheContainerTokenNeverCarriesAHomeDirectory() throws {
        let paths = ["/private/var/mobile/Containers/Shared/AppGroup/28A6DD4E-1E1F",
                     "/Users/vorname/Library/Developer/CoreSimulator/Devices/876E/data/Containers/Shared/AppGroup/AB12",
                     "/Users/vorname/Library/Group Containers/group.com.aiity.haiity"]
        let tokens = ["28A6DD4E-1E1F", "AB12", "group.com.aiity.haiity"]
        for (path, expected) in zip(paths, tokens) {
            let token = try XCTUnwrap(DiagnosticsFacts.containerToken(path))
            XCTAssertEqual(token, expected)
            XCTAssertFalse(token.contains("/"), "ein Pfadteil ist kein Pfad: \(token)")
            XCTAssertFalse(token.contains("vorname"),
                           "der Kontoname eines Menschen im Bericht: \(token)")
        }
        XCTAssertNil(DiagnosticsFacts.containerToken(nil))
        XCTAssertNil(DiagnosticsFacts.containerToken(""))
        XCTAssertNil(DiagnosticsFacts.containerToken("/"))

        // Und das Sammeln reicht den rohen Pfad gar nicht erst durch. (Es
        // steht seit dem Melde-Blatt im Modell: zwei Oberflächen brauchen
        // denselben Stand, siehe `DiagnosticsCollector`.)
        let collector = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(collector.contains(
            "facts.appGroupContainer = DiagnosticsFacts.containerToken("))
        XCTAssertFalse(collector.contains("facts.appGroupContainer = FileManager"))
    }

    /// **Weder Seite noch Sammler fassen die Quellen an, an denen Namen
    /// liegen.** `DiagnosticsFacts` kann keinen Namen tragen — aber die Seite
    /// könnte ihn anzeigen, und der nächste Mensch schriebe ihn dann „nur
    /// kurz" in den Bericht. Besonders scharf ist `.content`: Titel und Text
    /// einer geplanten Mitteilung lauten „Zeit für <Habit-Name>", und
    /// `UNNotificationRequest.content` ist der einzige Weg dorthin.
    ///
    /// **Warum das Verbot auf `PersonalName` genauer geworden ist.** Die
    /// Entwicklerseite zeigt seit der Melde-Runde die Apple-KENNUNG dieses
    /// Geräts (`PersonalName.appleUserID`) — der Besitzer kann sie sonst nicht
    /// ablesen, und ohne sie ist `DeveloperAccess.ownerAppleUserID` nicht
    /// einzutragen. Eine undurchsichtige Zeichenfolge, die Apple je
    /// (Entwicklerteam, Apple-ID) vergibt, ist kein Name: aus ihr lässt sich
    /// kein Mensch ablesen, und sie steht auch NICHT im Bericht. Verboten
    /// bleiben deshalb genau die Zugriffe, die einen Namen liefern.
    func testDeveloperViewNeverReadsNamesEmojisOrNotificationText() throws {
        let files = ["Haiity/Views/DeveloperView.swift", "Haiity/Models/Diagnostics.swift"]
        for file in files {
            let text = try source(file)
            for leak in [".name", ".emoji", ".content", "log.values", "Celebration",
                         "PersonalName.effective", "PersonalName.alias",
                         "PersonalName.appleName", "PersonalName.resolve"] {
                XCTAssertFalse(text.contains(leak),
                               "\(file) liest \(leak) — das trägt einen Namen")
            }
        }
        // Was der Sammler stattdessen liest: Kennung, Anzahl, ältester
        // Schlüssel.
        let collector = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(collector.contains("request.identifier"))
        XCTAssertTrue(collector.contains("$1.log.count"), "vom Log darf nur die ANZAHL kommen")
        XCTAssertTrue(collector.contains("$0.log.keys"), "vom Log darf nur der SCHLÜSSEL kommen")
        let developer = try source("Haiity/Views/DeveloperView.swift")
        XCTAssertTrue(developer.contains("DiagnosticsReport.text(facts)"),
                      "kopiert werden darf nur der geprüfte Bericht")
    }

    /// **Die Kennung einer Mitteilung steht wörtlich im Bericht** — also darf
    /// sie keinen Namen enthalten. Sie wird aus UUIDs und Tagesschlüsseln
    /// gebaut; der Habit-Name lebt ausschließlich im `content`, der nirgends
    /// in den Bericht führt.
    func testReminderIdentifiersAreBuiltFromIdsNotNames() throws {
        let reminders = try source("Haiity/Services/Reminders.swift")
        XCTAssertTrue(reminders.contains(
            "static func habitReminderIdentifier(habitID: UUID, day: String) -> String"),
                      "die Kennung muss aus einer ID gebaut werden, nicht aus einem Habit")
        XCTAssertTrue(reminders.contains(#""\(habitReminderPrefix)\(habitID.uuidString)-\(day)""#))
        XCTAssertTrue(reminders.contains(#""\(sessionMilestonePrefix)\(session.id.uuidString)""#))

        for line in reminders.components(separatedBy: .newlines) where line.contains("dentifier") {
            XCTAssertFalse(line.contains(".name"),
                           "ein Habit-Name in einer Mitteilungs-Kennung landet im Bericht: \(line)")
            XCTAssertFalse(line.contains(".emoji"),
                           "ein Emoji in einer Mitteilungs-Kennung landet im Bericht: \(line)")
        }
    }

    // MARK: – Quell-Verträge: die Tür

    /// (a) **„Test-Mitteilung" ist aus „Mehr" verschwunden.** Sie war nie eine
    /// Einstellung, sondern eine Diagnose — und wohnt jetzt wortgleich und mit
    /// derselben Kennung auf der Entwicklerseite.
    func testMoreViewGaveUpTheTestNotification() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let notifications = try source("Haiity/Views/MoreNotifications.swift")
        for source in [more, notifications] {
            XCTAssertFalse(source.contains("testNotificationSection"),
                           "die Diagnosezeile steht wieder in den Einstellungen")
            XCTAssertFalse(source.contains("\"test-notification\""))
            XCTAssertFalse(source.contains("Reminders.scheduleTest"))
        }
    }

    /// (a) **Die Tür sitzt in `AboutView`** — sie sieht aus wie eine Fußzeile
    /// und ist eine: die Version gehört ohnehin in jede Meldung. Gerechnet
    /// wird in `DeveloperAccess`, geschrieben genau einmal, und der Stups beim
    /// Aufgehen macht die Geste bestätigt statt zufällig.
    func testAboutViewCarriesTheHiddenDoor() throws {
        let more = try source("Haiity/Views/AboutView.swift")
        XCTAssertTrue(more.contains("struct AboutView"))
        XCTAssertTrue(more.contains("\"app-version\""))
        XCTAssertTrue(more.contains("\"open-developer\""))
        XCTAssertTrue(more.contains("NavigationLink(value: MoreRoute.developer)"))
        XCTAssertTrue(more.contains("AppBuildInfo.versionLine"),
                      "Versionszeile und Bericht müssen denselben Ableseort haben")
        XCTAssertTrue(more.contains("DeveloperAccess.hint(for: taps)"))
        XCTAssertTrue(more.contains("DeveloperAccess.next(taps: taps)"))
        XCTAssertTrue(more.contains("Theme.Haptics.success()"))
        // Die Zeile „Entwickler" erscheint nur, wenn die Seite auf DIESEM
        // Gerät erreichbar ist — aufgeschlossen UND dem Besitzer gehörend
        // (siehe `FeedbackTests`, die beide Hälften einzeln festnagelt).
        XCTAssertTrue(more.contains("if developerAvailable"))
        // Genau EIN Schreibpunkt, und er schließt auf statt zu.
        XCTAssertEqual(more.components(separatedBy: "DeveloperAccess.isUnlocked = true").count - 1, 1)
        XCTAssertFalse(more.contains("DeveloperAccess.isUnlocked = false"),
                       "abgeschlossen wird auf der Entwicklerseite, nicht in Über")
    }

    /// (b) Die Kennungen, an denen die Simulator-Automatisierung hängt — und
    /// die beiden Aktionen, die ohne sichtbare Wirkung kaputt wirkten.
    func testDeveloperViewCarriesTheContractIdentifiers() throws {
        let developer = try source("Haiity/Views/DeveloperView.swift")
        for id in ["\"test-notification\"", "\"copy-diagnostics\"",
                   "\"reload-widgets\"",
                   // Ohne diese Zeile bliebe der Schlüssel für die
                   // Besitzer-Bindung hinter der Tür eingesperrt: Apple zeigt
                   // die Kennung nirgends an.
                   "\"copy-apple-user-id\""] {
            XCTAssertTrue(developer.contains(id), "Kennung fehlt: \(id)")
        }
        XCTAssertTrue(developer.contains("Reminders.scheduleTest()"),
                      "die verschobene Test-Mitteilung muss dieselbe Sache tun")
        XCTAssertTrue(developer.contains("UIPasteboard.general.string = DiagnosticsReport.text(facts)"))
        XCTAssertTrue(developer.contains("WidgetCenter.shared.reloadAllTimelines()"))
        XCTAssertFalse(developer.contains("DeveloperAccess.isUnlocked = false"))
        XCTAssertFalse(developer.contains("DeveloperAccess.isUnlocked = true"))
    }

    /// (b) **Der Stand steht, BEVOR der Store antwortet.** `Pro.product()`
    /// fragt den App Store; ohne Netz läuft das bis in den Zeitablauf der
    /// URL-Sitzung. Hinge der ganze Stand daran, zeigte die Seite minutenlang
    /// überall `n/a` — und weil ein leerer `DiagnosticsFacts` glatte Nullen
    /// hat, behauptete sie dabei „0 Habits, 0 geplante Mitteilungen". Genau
    /// das ist die Lage, in der jemand einen Fehler meldet: ein Gerät ohne
    /// Netz.
    func testTheFactsAreShownBeforeTheStoreAnswers() throws {
        let developer = try source("Haiity/Views/DeveloperView.swift")
        let published = try XCTUnwrap(developer.range(of: "collected = gathered"))
        let price = try XCTUnwrap(developer.range(of: "await DiagnosticsCollector.price()"))
        XCTAssertTrue(published.upperBound < price.lowerBound,
                      "der Preis aus dem Netz hält den ganzen Stand auf")

        // Vor dem Sammeln gibt es keinen Stand — kein leerer, der wie einer
        // aussieht — und deshalb auch nichts zu kopieren.
        XCTAssertTrue(developer.contains("@State private var collected: DiagnosticsFacts?"))
        XCTAssertTrue(developer.contains(".disabled(!isCollected)"),
                      "ein hohler Bericht ist antippbar")
        XCTAssertTrue(developer.contains("isCollected ? String(value) : nil"),
                      "eine 0 vor dem Sammeln ist eine Behauptung, keine Auskunft")
    }

    /// (b) **Der Bericht kennt seinen eigenen Moment** — und die eine Aktion
    /// dieser Seite, die berichtete Zahlen verändert, nimmt den Stand danach
    /// neu. Sonst verschickte jemand einen Bericht, in dem die gerade
    /// gestellte Test-Mitteilung fehlt.
    func testTheReportKnowsItsMomentAndTheTestNotificationRefreshesIt() throws {
        var facts = DiagnosticsFacts()
        facts.collectedAt = date("2026-08-14T18:41:00Z")
        XCTAssertTrue(DiagnosticsReport.text(facts)
            .contains("report.collected: 2026-08-14T18:41:00Z"))

        XCTAssertTrue(try source("Haiity/Models/Diagnostics.swift")
            .contains("facts.collectedAt = .now"))

        let developer = try source("Haiity/Views/DeveloperView.swift")
        let scheduled = try XCTUnwrap(developer.range(of: "Reminders.scheduleTest()"))
        let buttonEnd = try XCTUnwrap(
            developer.range(of: #"accessibilityIdentifier("test-notification")"#))
        XCTAssertTrue(developer[scheduled.upperBound..<buttonEnd.lowerBound]
            .contains("await collect()"),
                      "nach der Test-Mitteilung stimmen die gemeldeten Zahlen nicht mehr")
    }

    /// (b) **Die verschobene Test-Mitteilung hat ihren Ausgang behalten.** In
    /// „Mehr" schaltete der fehlgeschlagene Versuch den Sprung in die
    /// iOS-Einstellungen frei. Ohne ihn wäre der Satz „Benachrichtigungen sind
    /// deaktiviert" auf dieser Seite eine Sackgasse — und in „Mehr" kann der
    /// Hinweis nicht mehr erscheinen, weil das ein anderes Blatt ist.
    func testTheMovedTestNotificationKeptItsWayOut() throws {
        let developer = try source("Haiity/Views/DeveloperView.swift")
        XCTAssertTrue(developer.contains(#""open-notification-settings""#))
        XCTAssertTrue(developer.contains("UIApplication.openNotificationSettingsURLString"))
        XCTAssertTrue(developer.contains("if testFailed || isNotificationAccessDenied"),
                      "der Ausweg muss auch ungefragt erscheinen, wenn der Stand denied sagt")

        // Der Weg für die Zusammenfassungen bleibt, wo er hingehört.
        let more = try source("Haiity/Views/MoreNotifications.swift")
        XCTAssertTrue(more.contains(#""open-notification-settings""#))
    }

    /// (b) **Der Kalendertitel wird abgelesen, nicht behauptet.**
    /// `CalendarSync.calendarTitle` ist die Konstante, MIT der ein Kalender
    /// angelegt wird — sie meldete den Titel auch ohne Zugriff, ohne Quelle
    /// und nach dem Umbenennen. Ausgerechnet der Wert, wegen dem jemand diese
    /// Seite öffnet, wäre damit unfälschbar.
    func testTheCalendarTitleIsReadFromTheDeviceNotAsserted() throws {
        let collector = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(collector.contains("facts.calendarTitle = CalendarSync.activeCalendarTitle"))
        XCTAssertFalse(collector.contains("facts.calendarTitle = CalendarSync.calendarTitle"),
                       "die Konstante meldet einen Kalender, den es nicht geben muss")

        let sync = try source("Haiity/Services/CalendarSync.swift")
        let start = try XCTUnwrap(sync.range(of: "static func activeCalendarTitle(isReminder:"))
        let end = try XCTUnwrap(sync.range(of: "static var writableCalendarOptions",
                                           range: start.upperBound..<sync.endIndex))
        let body = sync[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(body.contains("hasAccess"), "ohne Zugriff gibt es keine Auskunft")
        XCTAssertTrue(body.contains("CalendarSyncPreferences.calendarTitleKey"),
                      "gelesen wird die gemerkte Überschrift, nicht EventKit")
        XCTAssertTrue(body.contains("defaults.string(forKey: calendarKey)"),
                      "ohne gemerkten Titel bleibt die gespeicherte Kennung die Auskunft")
        XCTAssertFalse(body.contains("store.calendar(withIdentifier:"),
                       "die Diagnose darf den Main Actor nicht auf EventKit warten")
        for write in ["EKCalendar(", "saveCalendar", "isEnabled ="] {
            XCTAssertFalse(body.contains(write), "die Diagnose darf nichts anlegen: \(write)")
        }
    }

    /// (b) **Reine Logik wohnt im Modell.** `AppBuildInfo` hat keine Ansicht,
    /// aber ZWEI Ansichten hängen daran (`AboutView` in „Mehr" und die
    /// Entwicklerseite). Läge der Typ in einer der beiden Bildschirmdateien,
    /// müsste die andere sie für zwei Zahlen mitnehmen.
    func testAppBuildInfoLivesInTheModelNotInAView() throws {
        XCTAssertTrue(try source("Haiity/Models/Diagnostics.swift").contains("enum AppBuildInfo"))
        XCTAssertFalse(try source("Haiity/Views/DeveloperView.swift").contains("enum AppBuildInfo"))
        XCTAssertFalse(try source("Haiity/Views/MoreView.swift").contains("enum AppBuildInfo"))
    }

    /// (c) **Kein `#if DEBUG` um diese Seite.** Eine Meldung entsteht nicht
    /// auf dem Rechner der Entwicklung, sondern auf dem Gerät eines Menschen
    /// mit einem Release-Build aus dem App Store — genau dort muss die Seite
    /// Auskunft geben können. Geprüft werden echte Übersetzer-Anweisungen
    /// (Zeilenanfang), nicht das Wort in einem Kommentar: der Kommentar
    /// erklärt ja gerade, warum es die Klammer NICHT gibt.
    func testTheDeveloperAreaIsNotBehindADebugFlag() throws {
        XCTAssertTrue(try directives(in: "Haiity/Views/DeveloperView.swift").isEmpty,
                      "die Entwicklerseite steht hinter einer Übersetzer-Klammer")

        // In `Diagnostics.swift` gibt es genau eine Klammer, und sie LÄSST
        // nichts weg — sie berichtet, welcher Build läuft.
        XCTAssertEqual(try directives(in: "Haiity/Models/Diagnostics.swift"),
                       ["#if DEBUG", "#else", "#endif"])
        let diagnostics = try source("Haiity/Models/Diagnostics.swift")
        let configuration = try XCTUnwrap(diagnostics.range(of: "static var currentConfiguration"))
        let klammer = try XCTUnwrap(diagnostics.range(of: "\n        #if DEBUG"))
        XCTAssertTrue(configuration.upperBound < klammer.lowerBound,
                      "die einzige Klammer gehört zur Konfigurations-Meldung")

        // Die Tür selbst rechnet ohne jede Klammer.
        let doorStart = try XCTUnwrap(diagnostics.range(of: "enum DeveloperAccess"))
        let doorEnd = try XCTUnwrap(diagnostics.range(of: "struct DiagnosticsFacts"))
        XCTAssertFalse(diagnostics[doorStart.lowerBound..<doorEnd.lowerBound].contains("#if"))
    }

    /// (c) Die Freischaltung rechnet pur und schreibt an genau einer Stelle —
    /// und zwar in `UserDefaults.standard`, nicht in die App-Group.
    ///
    /// **Warum die App-Group-Prüfung auf den Türbereich zeigt.** In derselben
    /// Datei wohnt seit der Melde-Runde auch `DiagnosticsCollector`, und der
    /// MUSS in den geteilten Topf greifen: dort liegen Container und
    /// Kalender-Zuordnung, und genau die berichtet er. Der Satz, um den es
    /// hier geht, gilt der Tür: eine Freischaltung im geteilten Topf läge im
    /// selben Behälter wie Kauf- und Kalenderzustand und wäre später schwerer
    /// wieder loszuwerden.
    func testDeveloperAccessStaysPureAndAppLocal() throws {
        let diagnostics = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(diagnostics.contains("UserDefaults.standard.bool(forKey: unlockedKey)"))
        XCTAssertTrue(diagnostics.contains("UserDefaults.standard.set(newValue, forKey: unlockedKey)"))
        let doorStart = try XCTUnwrap(diagnostics.range(of: "enum DeveloperAccess"))
        let doorEnd = try XCTUnwrap(diagnostics.range(of: "struct DiagnosticsFacts"))
        let door = diagnostics[doorStart.lowerBound..<doorEnd.lowerBound]
        XCTAssertFalse(door.contains("SharedStorage.appGroup"),
                       "die Freischaltung gehört nicht in den geteilten Topf")
        // Weder `hint` noch `next` fassen eine Ablage an — sonst wäre die
        // Fortschaltung nicht ohne Zustand prüfbar.
        let hintStart = try XCTUnwrap(diagnostics.range(of: "static func hint(for taps: Int)"))
        let nextEnd = try XCTUnwrap(diagnostics.range(of: "/// Alles, was der Entwicklerbereich"))
        XCTAssertFalse(diagnostics[hintStart.lowerBound..<nextEnd.lowerBound].contains("UserDefaults"))
    }

    /// (c) Die beiden deutschen Schlüssel des Countdowns: Einzahl und Mehrzahl
    /// getrennt, mit typografischem Auslassungszeichen (…) statt drei Punkten
    /// und ohne ASCII-Anführungszeichen — sonst zerlegt der Katalog-Lauf sie.
    func testTheHintKeysAreGermanAndTypographic() throws {
        let diagnostics = try source("Haiity/Models/Diagnostics.swift")
        XCTAssertTrue(diagnostics.contains("if remaining == 1"),
                      "ohne diese Verzweigung stünde beim letzten Tipp die Mehrzahl")
        XCTAssertTrue(diagnostics.contains(#"String(localized: "Noch ein Tipp …")"#))
        XCTAssertTrue(diagnostics.contains(#"String(localized: "Noch \(remaining) Tipps …")"#))
        XCTAssertFalse(diagnostics.contains("Tipp ..."))
        XCTAssertFalse(diagnostics.contains("Tipps ..."))
    }

    /// (d) **Die Route ist der EINE Ort, an dem steht, welche Seite hinter
    /// welchem Ziel liegt.** `developer` ist bewusst kein Deep-Link-Ziel: ein
    /// `haiity://developer` wäre eine zweite, offene Tür neben der versteckten.
    func testMoreRouteAndContentViewKnowTheDeveloperPage() throws {
        XCTAssertEqual(MoreRoute.developer.id, .developer)
        for host in ["about", "developer", "appearance", "habitBehavior", "github",
                     "dataTransfer", "calendar", "notifications", "personalization", "localModel"] {
            XCTAssertNil(AppDestination.resolve(url: URL(string: "haiity://\(host)")!),
                         "The settings child \(host) must not acquire an external route")
        }

        let content = try source("Haiity/Views/ContentView.swift")
        let destination = try XCTUnwrap(content.range(of: "private func moreDestination"))
        let developer = try XCTUnwrap(content.range(of: "case .developer:",
            range: destination.upperBound..<content.endIndex))
        let page = try XCTUnwrap(content.range(of: "DeveloperView(store: store, cloudStatus: cloudStatus)",
            range: developer.upperBound..<content.endIndex))
        let gate = content[developer.upperBound..<page.lowerBound]
        XCTAssertTrue(gate.contains("DeveloperAccess.isAvailable"),
                      "The destination must recheck ownership before mounting developer tools")
        XCTAssertTrue(gate.contains("storedAppleUserID: PersonalName.appleUserID"))
        XCTAssertTrue(gate.contains("storedAppleEmail: PersonalName.appleEmail"))
        XCTAssertFalse(content.contains("\"developer\""),
                       "ein Deep-Link auf den Entwicklerbereich hebelt die versteckte Tür aus")
        let host = try XCTUnwrap(content.range(of: ".sheet(item: $moreSheet,"))
        let hostEnd = try XCTUnwrap(content.range(of: ".fullScreenCover(isPresented: $showReminderSetup)",
            range: host.upperBound..<content.endIndex))
        let sheet = content[host.upperBound..<hostEnd.lowerBound]
        XCTAssertTrue(sheet.contains("NavigationStack(path: $moreSheetPath)"))
        XCTAssertTrue(sheet.contains(".navigationDestination(for: MoreRoute.self, destination: moreDestination)"),
                      "Settings children must push into the presented settings stack")
        XCTAssertFalse(sheet.contains(".sheet("), "A settings child must not create a nested sheet host")
    }

    // MARK: – Quell-Verträge: der Katalog

    /// (e) **Die Liste holt sich der Test selbst aus dem Quelltext.** Eine von
    /// Hand gepflegte Aufzählung wäre schon beim nächsten hinzugefügten
    /// Schlüssel unvollständig — und ein vergessener Schlüssel fällt auf
    /// einem englischen Gerät als deutscher Satz auf, den niemand liest.
    func testEveryDeveloperKeyIsInTheCatalog() throws {
        let strings = try catalog()
        var keys = try localizedKeys(in: source("Haiity/Views/DeveloperView.swift"))
        XCTAssertGreaterThan(keys.count, 24, "die Schlüssel-Suche hat fast nichts gefunden")
        // Die Zeile hinter der Tür und der Countdown: der eine steht in
        // `AboutView`, der andere trägt eine Interpolation und heißt im
        // Katalog deshalb anders (`%lld`).
        keys.formUnion(["Entwickler", "Noch ein Tipp …", "Noch %lld Tipps …"])
        for key in keys.sorted() {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
        // Der Datenschutz-Satz unter den Aktionen ist das Versprechen, das
        // diese Datei prüft — er darf in keiner Sprache fehlen.
        XCTAssertNotNil(strings["Der kopierte Text enthält keine Habit-Namen, keine Emojis und keine Werte — nur Zahlen, Zustände und technische Kennungen."])
    }

    /// (e) **Umgekehrter Vertrag.** Der Bericht wird NIE übersetzt, und Namen,
    /// die in jeder Sprache gleich heißen, gehören in keinen Katalog — sie
    /// laufen über `Text(verbatim:)`. Ein Eintrag hier wäre eine Einladung an
    /// 16 Übersetzungen, den Bericht unlesbar zu machen.
    func testNeitherTheReportNorTheVerbatimNamesAreTranslatable() throws {
        let strings = try catalog()
        for key in ["hAiity Diagnose", DiagnosticsReport.unknown] + Self.reportKeys {
            XCTAssertNil(strings[key], "der Bericht darf nicht übersetzbar sein: \(key)")
        }
        for name in ["iCloud", "hAiity Pro", "iOS", "Bundle-ID", "Produkt-ID",
                     "App-Group", "data.json"] {
            XCTAssertNil(strings[name], "heißt in jeder Sprache gleich: \(name)")
        }
        XCTAssertNil(strings[AppBuildInfo.versionLine],
                     "die Versionszeile sind zwei Zahlen und ein Markenname")
    }

    // MARK: – Werkzeug

    /// Jede Zeile, die der Bericht immer bringt — in genau dieser Reihenfolge.
    private static let reportKeys = [
        "report.collected",
        "app.version", "app.build", "app.bundle", "app.configuration", "app.ios", "app.device",
        "data.habits.active", "data.habits.archived", "data.log.entries", "data.log.oldest",
        "data.file.bytes", "data.file.modified", "data.appgroup",
        "cloud.status",
        "notifications.authorization", "notifications.pending", "notifications.next",
        "calendar.enabled", "calendar.title", "calendar.events",
        "pro.unlocked", "pro.product", "pro.price",
    ]

    /// Ein voller Stand — jedes Feld belegt, damit keine Zeile aus Versehen
    /// über einen leeren Wert durchrutscht.
    private func filledFacts() -> DiagnosticsFacts {
        var facts = DiagnosticsFacts()
        facts.collectedAt = date("2026-08-14T18:41:00Z")
        facts.appVersion = "1.2.3"
        facts.build = "44"
        facts.bundleID = "com.aiity.haiity"
        facts.configuration = "Release"
        facts.systemVersion = "26.4.1"
        facts.deviceModel = "iPhone18,2"
        facts.activeHabits = 7
        facts.archivedHabits = 2
        facts.logEntries = 1234
        facts.oldestLogDay = "2024-01-31"
        facts.dataFileBytes = 692
        facts.dataFileModified = date("2026-08-14T18:41:00Z")
        facts.appGroupContainer = "28A6DD4E-1E1F-4C6E-9A2B-0F5D3C7A11B9"
        facts.cloudStatus = "active 2026-08-14T18:41:00Z"
        facts.notificationAuthorization = "authorized"
        facts.pendingNotifications = 9
        facts.nextNotifications = [(id: "summary", date: date("2026-08-15T06:00:00Z")),
                                   (id: "summary-weekly", date: date("2026-08-16T18:00:00Z"))]
        facts.calendarEnabled = true
        facts.calendarTitle = "hAiity"
        facts.calendarEvents = 12
        facts.proUnlocked = true
        facts.proProductID = "com.aiity.haiity.pro"
        facts.proPrice = "4,99 €"
        return facts
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? .distantPast
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

    /// Echte Übersetzer-Anweisungen einer Datei: nur, was am Zeilenanfang
    /// steht. Das Wort in einem Kommentar ist keine Klammer.
    private func directives(in relative: String) throws -> [String] {
        try source(relative)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#if") || $0.hasPrefix("#else") || $0.hasPrefix("#endif") }
    }

    /// Alle deutschen Schlüssel einer Quelldatei. Interpolierte Schlüssel
    /// (`\(remaining)`) fallen bewusst heraus — sie heißen im Katalog anders
    /// (`%lld`) und werden von Hand nachgereicht.
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
