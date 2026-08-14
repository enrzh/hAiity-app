# App-Store-Listing — hAiity

Quelltexte für App Store Connect. Deutsch ist die Quellsprache der App
(`CFBundleDevelopmentRegion: de`), Englisch die zweite Pflichtsprache.

Alle Angaben sind gegen den Code geprüft: nur Funktionen, die im Build
existieren, stehen hier. Zeichenlimits stehen jeweils dahinter.

**Zum Kopieren:** In den Codeblöcken ist jeder Absatz genau EINE Zeile —
absichtlich, denn App Store Connect übernimmt Zeilenumbrüche wörtlich, und
hart umbrochener Fließtext sieht auf schmalen Geräten zerfranst aus. Beim
Einfügen nichts nachformatieren.

---

## DE — Deutsch (Primärsprache)

### App-Name (max. 30)

**`hAiity – Habits als Raster`** (26)

Ausweichvarianten, falls der Name belegt ist:

| Vorschlag | Zeichen |
| --- | --- |
| `hAiity – Habits als Raster` | 26 |
| `hAiity – Habit-Raster` | 21 |
| `hAiity Habits` | 13 |
| `hAiity – Dein Jahr in Quadraten` | 31 — über dem Limit, nicht nutzen |

### Untertitel (max. 30)

**`Gewohnheiten als Jahresraster`** (29)

### Promotional Text (max. 170)

```
Ein Raster je Habit, ein Quadrat je Tag. Ohne Konto, ohne Server, ohne Tracking. Deine Daten bleiben auf dem iPhone — und, wenn du willst, in deiner privaten iCloud.
```

(165 Zeichen, eine einzige Zeile.)

### Beschreibung (max. 4000, hier 2.895)

```
hAiity füllt Quadrate. Jeder Tag, an dem du dranbleibst, färbt eine Zelle — dein Jahr als Raster, ein eigenes Raster für jedes Habit. Wer den Beitragsgraphen auf GitHub kennt, kennt die Idee.

KEIN KONTO. KEIN SERVER. KEIN TRACKING.
Deine Habits liegen als Datei auf deinem iPhone. Ist das Gerät bei iCloud angemeldet, spiegelt hAiity sie zusätzlich in deine eigene private iCloud — ein Datensatz in der privaten Datenbank deiner Apple-ID. Wir sehen sie nie: Bei uns gibt es keine Stelle, an der sie ankommen könnten. Ohne iCloud läuft alles genauso, nur ohne Spiegel.

DAS RASTER
• 53 Wochen x 7 Tage je Habit, Monatsmarken darüber
• Fünf Farbstufen: je mehr an einem Tag, desto satter das Quadrat
• Vergangene Tage nachtragen, mit dem Datum vor Augen

DREI ARTEN VON HABIT
• Abhaken — erledigt oder nicht
• Menge — ein Zählstand pro Tag, ab dem Ziel zählt der Tag
• Ja/Nein — „Kein Zucker?“ Ja ist Erfolg, Nein eine Antwort, unbeantwortet etwas Drittes

WIEDERHOLUNG WIE IM KALENDER
Täglich, wöchentlich, monatlich, jährlich — mit Intervall, Wochentagen, Monatstag, „dritter Dienstag“, Ende nach Datum oder Anzahl. Oder flexibel: „3x pro Woche, egal wann“.

SERIEN UND STATISTIK
Aktuelle und beste Serie, Tages- und Wochenquote, Check-ins gesamt, Jahres-Puls über alle Habits.

WIDGETS UND SPERRBILDSCHIRM
Home-Bildschirm: ein Habit mit Serie und Abhak-Knopf, das nackte Raster, eine Übersicht mehrerer Habits. Sperrbildschirm: Tagesring, Serie als Zeile oder Textzeile. Plus Steuerelement im Kontrollzentrum (ab iOS 18).

SIRI UND KURZBEFEHLE
„hAiity Lesen erledigt“, „Was ist in hAiity noch offen“, „hAiity Serie von Sport“. Abhaken, Nein notieren, Tagesstand und Serie abfragen.

MITTEILUNGEN
Erinnerung je Habit, Tages- und Wochenzusammenfassung. Um Erlaubnis wird erst gefragt, wenn du eine einschaltest — nie beim Start.

KALENDER-SPIEGEL
hAiity legt einen eigenen Kalender an und pflegt darin die Termine deiner Habits. Deine übrigen Kalender bleiben unberührt.

GLÜCKWUNSCH ZUM PERFEKTEN TAG
Alles erfüllt, was heute anstand? Dann gibt es einen Glückwunsch — auf dem Gerät getextet, mit deinem Namen.

AUSSERDEM
18 App-Icons, eingebaute Farbfamilien, kompakte Ansicht, Wischaktionen, Sessions mit Live-Aktivität, Archiv statt Löschen, Habit als Bild teilen, Export und Import als JSON (ein Import führt zusammen, er überschreibt nie), Deutsch und 16 weitere Sprachen, Dynamic Type, VoiceOver, „Bewegung reduzieren“.

FREI UND hAiity PRO
Frei: drei aktive Habits, alle Habit-Arten, Serien, Widgets, Siri, Mitteilungen, Glückwunsch, Export, alle 18 Icons, die eingebauten Farben. Das Limit gilt nur beim Anlegen — Bestehendes bleibt voll nutzbar, archivierte Habits zählen nicht mit.
hAiity Pro: unbegrenzt viele Habits, eigene Farben, App-Icon per Farbrad, Kalender-Spiegel, volle Statistik.
Einmal kaufen. Kein Abo, kein Konto, kein Server. Familienfreigabe inbegriffen.

Erfordert iOS 17.
```

Zum Kürzen auf ~2.500, falls gewünscht: zuerst „MITTEILUNGEN“, dann
„SERIEN UND STATISTIK“ streichen — beide stehen auch in der Feature-Liste
unter „AUSSERDEM“ bzw. auf dem Statistik-Screenshot. Die ersten drei Zeilen
(bis „KEIN KONTO“) sind das, was ohne Aufklappen sichtbar ist; alles
darunter liest nur, wer schon interessiert ist.

### Keywords (max. 100, komma-separiert, ohne App-Namen)

```
habit,tracker,routine,serie,streak,ziele,check-in,widget,siri,kalender,statistik,offline,ohne konto
```

(99 Zeichen. Keine Leerzeichen nach Kommas — die zählen mit. „Gewohnheiten“
und „Raster“ stehen bereits in Name/Untertitel und müssen hier nicht
wiederholt werden.)

### Was ist neu (erste Version)

```
Die erste Version von hAiity.
```

---

## EN — English (U.S.)

### App Name (max. 30)

**`hAiity – Habit Grid Tracker`** (27)

| Alternative | Chars |
| --- | --- |
| `hAiity – Habit Grid Tracker` | 27 |
| `hAiity – Your Year in Squares` | 29 |
| `hAiity Habits` | 13 |

Bewusst **ohne** „GitHub“ in Name, Untertitel und Keywords: fremde Marke,
unnötiges Ablehnungsrisiko (Guideline 5.2.1). In der Beschreibung steht die
Anspielung genau einmal und rein beschreibend („wer den Beitragsgraphen auf
GitHub kennt“) — kein Logo, keine behauptete Verbindung, keine
GitHub-Funktion. Wer auch dieses Restrisiko nicht will, streicht den Satz;
die Beschreibung trägt ohne ihn genauso.

### Subtitle (max. 30)

**`Your year of habits, one grid`** (29)

### Promotional Text (max. 170)

```
One grid per habit, one square per day. No account, no server, no tracking. Your data stays on your iPhone — and, if you want, in your own private iCloud.
```

(154 characters, a single line.)

### Description (max. 4000, 2,833 here)

```
hAiity fills squares. Every day you show up colors a cell — your year as a grid, one grid per habit. If you know the contribution graph on GitHub, you know the idea.

NO ACCOUNT. NO SERVER. NO TRACKING.
Your habits live in a file on your iPhone. If the device is signed into iCloud, hAiity also mirrors them into your own private iCloud — a single record in the private database of your Apple ID. We never see them: there is no place on our side for them to arrive. Without iCloud everything works the same, just without the mirror.

THE GRID
• 53 weeks x 7 days per habit, month markers on top
• Five color levels: the more you did that day, the deeper the square
• Backfill past days, with the date in front of you

THREE KINDS OF HABIT
• Checkbox — done or not
• Quantity — a count per day; the day counts once it reaches your target
• Yes/No — "No sugar?" Yes is a success, No is an answer, unanswered is a third thing

CALENDAR-GRADE RECURRENCE
Daily, weekly, monthly, yearly — with an interval, weekdays, day of month, "third Tuesday", ending on a date or after a count. Or flexible: "3x per week, whenever".

STREAKS AND STATISTICS
Current and best streak, daily and weekly rate, total check-ins, a year pulse across all habits.

WIDGETS AND LOCK SCREEN
Home Screen: one habit with streak and a check-off button, the bare grid, a roster of several habits. Lock Screen: a day ring, your streak as a row or a line of text. Plus a Control Center control (iOS 18 and later).

SIRI AND SHORTCUTS
"Check off Reading in hAiity", "What's left in hAiity today", "What's my Running streak in hAiity". Check off, log a No, ask for today's status or a streak.

NOTIFICATIONS
A reminder per habit, a daily and a weekly summary. Permission is asked only when you turn one on — never at launch.

CALENDAR MIRROR
hAiity creates its own calendar and keeps your habit events in it. Your other calendars stay untouched.

A PERFECT DAY, CELEBRATED
Everything that was due today, done? Then you get a note — written on the device, with your name if you gave one.

ALSO
18 app icons, built-in color families, compact layout, swipe actions, sessions with a Live Activity, archive instead of delete, share a habit as an image, JSON export and import (an import merges, it never overwrites), German plus 16 more languages, Dynamic Type, VoiceOver, Reduce Motion.

FREE AND hAiity PRO
Free: three active habits, every habit kind, streaks, widgets, Siri, notifications, the perfect-day note, JSON export, all 18 icons, the built-in colors. The limit applies only when creating — what you already have stays fully usable, and archived habits do not count.
hAiity Pro: unlimited habits, custom colors, the app icon from a color wheel, the calendar mirror, the full statistics.
Buy once. No subscription, no account, no server. Family Sharing included.

Requires iOS 17.
```

### Keywords (max. 100, comma separated, no app name)

```
habit,tracker,routine,streak,goals,daily,checklist,widget,siri,calendar,stats,offline,no account
```

(96 characters. No spaces after commas — they count.)

### What's New (first version)

```
The first version of hAiity.
```

---

## Kategorie-Empfehlung

| Feld | Empfehlung | Begründung |
| --- | --- | --- |
| Primäre Kategorie | **Productivity** | hAiity trackt beliebige Gewohnheiten (Lesen, Üben, Papierkram), nicht Gesundheit. Die Metapher ist ein Beitragsraster, kein Fitness-Log. Der Wettbewerb ist in Productivity dünner besetzt als in Health & Fitness. |
| Sekundäre Kategorie | **Health & Fitness** | Fängt die Suchintention „Gewohnheiten für Sport/Trinken/Schlaf“ mit ab, ohne Gesundheitsdaten zu versprechen. |

Wichtig: Die App liest und schreibt **kein** HealthKit. Health & Fitness nur
als Sekundärkategorie wählen und in der Beschreibung nichts Medizinisches
behaupten.

## Altersfreigabe

**4+**

Im ASC-Fragebogen alle Fragen mit „Keine/None“ beantworten:

| Frage | Antwort |
| --- | --- |
| Gewalt (fiktiv, realistisch), Schreckensszenarien | Keine |
| Sexualität, Nacktheit, Anzüglichkeit | Keine |
| Profanität, derber Humor | Keine |
| Alkohol, Tabak, Drogen | Keine |
| Simuliertes Glücksspiel, Glücksspiel mit echtem Geld | Nein |
| Horror-/Angstthemen | Keine |
| Medizinische/Behandlungsinformationen | Keine |
| Uneingeschränkter Web-Zugriff | Nein (die App öffnet keinen Browser; nur `UIApplication.openSettingsURLString`) |
| Nutzergenerierte Inhalte / Chat | Nein (Habit-Namen sind privat und verlassen das Gerät nicht) |
| Standortbezogene Funktionen | Nein |
| Häufige/intensive Preisgabe personenbezogener Daten | Nein |

In-App-Käufe ändern die Altersfreigabe nicht; „Enthält In-App-Käufe“ wird
separat aus dem IAP-Eintrag abgeleitet.

---

## Review-Notizen an Apple (EN — paste into "Notes" in App Review Information)

```
NO LOGIN REQUIRED
hAiity has no accounts and no backend of any kind. There is nothing to sign in to and no demo credentials are needed — the app is fully functional the moment it launches. Habit data is stored in a JSON file inside the app group container on device.

ICLOUD
If the device is signed into iCloud, the app mirrors that one file into the user's OWN private CloudKit database (container iCloud.com.aiity.haiity, private database, a single record). We operate no server and cannot read that data. If the device is signed out of iCloud or offline, the app works identically and a status row in "More" states that plainly. Reviewers do not need an iCloud account to test anything.

WHY FULL CALENDAR ACCESS (NSCalendarsFullAccessUsageDescription)
The optional "habits in calendar" feature creates a dedicated hAiity calendar and keeps the user's habit events in it. Maintaining our own events — updating a title or time, removing an event when the habit changes or is deleted, and avoiding duplicates on re-sync — requires finding those events again, and finding requires READ access. EKEventStore's write-only access cannot fetch existing events, so it is not sufficient for a mirror that must stay in sync rather than append forever. The app only ever touches the calendar it created itself; all other calendars and events are left untouched. The feature is off by default and the permission is requested only when the user turns it on. Everything else in the app works without it.

SIGN IN WITH APPLE IS OPTIONAL AND IS NOT A LOGIN
The app offers Sign in with Apple in Settings for exactly one purpose: to learn the user's FIRST NAME so notifications can address them (for example the "perfect day" congratulation). The identity token is never inspected, never stored and never transmitted; only the given name is written to UserDefaults in the app group and never leaves the device. A free-text alias field sits directly above it and takes precedence, so the feature is fully usable without ever signing in. Because the app has no authentication at all and offers no third-party login, Guideline 4.8 does not apply.

NOTIFICATIONS
Permission is requested only when the user enables a reminder or a summary — never at launch.

IN-APP PURCHASE
com.aiity.haiity.pro is a NON-CONSUMABLE, ONE-TIME purchase (no subscription, no auto-renewal), with Family Sharing enabled. Free tier: up to 3 ACTIVE habits (archived habits do not count). The limit applies only when CREATING a habit — existing data always stays fully usable, nothing is locked away retroactively. Pro unlocks unlimited habits, custom colors, setting the app icon from a color wheel (it snaps to the nearest of the 18 bundled icons — all 18 are tappable for free), the calendar mirror and the full statistics screen. The paywall can be reached from six places: creating a fourth habit, the "hAiity Pro" row in Settings, Settings > custom color, Settings > icon color wheel, Settings > habits in calendar, and the statistics screen. A "Restore purchases" button is on the paywall. The entitlement is cached locally in the app group; there is no receipt server.

ANALYTICS
None. No third-party SDKs, no tracking, no advertising identifiers. The privacy manifest declares NSPrivacyTracking=false and an empty NSPrivacyCollectedDataTypes in both the app and the widget extension.
```

---

## ASC-Privacy-Fragebogen (App-Datenschutz)

Einstiegsfrage **„Erfasst du oder erfassen deine Drittanbieter Daten aus
dieser App?“** → **Nein**. Damit endet der Fragebogen mit **„Data Not
Collected“** für alle Kategorien. Die Tabelle dokumentiert, warum das für
jede Kategorie stimmt.

Apples Definition zählt nur Daten, die die App vom Gerät **an einen Server
sendet, auf den der Entwickler Zugriff hat**. hAiity sendet nichts: Es gibt
keinen hAiity-Server. Der iCloud-Spiegel schreibt in die **private
CloudKit-Datenbank des Nutzers**; Daten in der privaten Datenbank des Nutzers
gelten nicht als vom Entwickler erfasst.

| Kategorie | Antwort | Warum |
| --- | --- | --- |
| Contact Info — Name | **Not Collected** | Vorname aus optionaler Apple-Anmeldung bzw. frei getippter Alias, nur für die Anrede in Mitteilungen. Liegt in den App-Group-Defaults, verlässt das Gerät nie. |
| Contact Info — E-Mail, Telefon, Adresse, sonstige | **Not Collected** | Wird nie erfragt und nie ausgelesen. Aus der Apple-Anmeldung wird neben dem Vornamen nur die undurchsichtige Kennung (`ASAuthorizationAppleIDCredential.user`) gerätelokal abgelegt — sie entscheidet ausschließlich, ob der versteckte Entwicklerbereich auf diesem Gerät aufgeht, und verlässt das Gerät nie. Schickt ein Nutzer von sich aus eine Fehlermeldung (Schütteln → Formular → sein eigenes Mail-Programm), sehen wir dabei seine Absenderadresse; das ist seine Mail an uns, keine Erhebung durch die App (Apples Ausnahme für nutzerinitiierte Support-/Fehlermeldungen). |
| Health & Fitness | **Not Collected** | Kein HealthKit, keine Health-Berechtigung im Entitlement. Habit-Namen kann der Nutzer frei wählen, sie bleiben auf dem Gerät. |
| Financial Info | **Not Collected** | Zahlung läuft vollständig über Apples In-App-Kauf; die App sieht keine Zahlungsdaten. |
| Location | **Not Collected** | Keine Standort-API, kein `NSLocation…UsageDescription`. |
| Sensitive Info | **Not Collected** | Wird nicht erhoben. |
| Contacts | **Not Collected** | Kein Kontakte-Zugriff. |
| User Content — sonstige Inhalte (Habits, Check-ins, Notizen) | **Not Collected** | `data.json` im App-Group-Container; optional gespiegelt in die private CloudKit-DB des Nutzers. Kein Empfänger auf unserer Seite. Export/Import ist eine reine Nutzeraktion über den Teilen-Dialog. |
| User Content — Fotos/Video, Audio, Kundendienst | **Not Collected** | Kein Zugriff auf Fotos, Mikrofon oder Kamera. Die Teilen-Karte rendert ein Bild lokal und übergibt es an den Teilen-Dialog des Systems. |
| Browsing History | **Not Collected** | Kein Browser, kein WKWebView. |
| Search History | **Not Collected** | Die Suche filtert nur die lokale Liste und wird nicht gespeichert. |
| Identifiers — User ID, Device ID | **Not Collected** | Keine Konten, keine IDFA/IDFV-Nutzung, kein Analytics-SDK. Habit-UUIDs sind gerätelokal und identifizieren keine Person. |
| Purchases — Kaufhistorie | **Not Collected** | Der Berechtigungsstatus kommt von StoreKit und wird nur lokal in den App-Group-Defaults zwischengespeichert (`proUnlocked`). Kein Quittungs-Server. |
| Usage Data — Produktinteraktion, Werbedaten, sonstige | **Not Collected** | Keine Telemetrie. |
| Diagnostics — Crash-, Performance-, sonstige Diagnosedaten | **Not Collected** | Kein Crash-SDK, keine automatische Übertragung. Schüttelt der Nutzer das Gerät, öffnet die App ein Formular: seine Beschreibung plus ein vollständig einsehbarer, aufklappbarer Diagnosetext (Version, Build, Gerätemodell, iOS, Zähler, Zustände — bauartbedingt ohne Habit-Namen, Emojis, Werte und Namen). Abgeschickt wird er vom Nutzer selbst über `MFMailComposeViewController` bzw. das System-Teilen-Blatt, jederzeit abschaltbar („Mehr → Schütteln zum Melden", Standard EIN). Das fällt unter Apples Ausnahme für **nutzerinitiierte Fehler- und Supportmeldungen**: optional, sichtbar, nicht mit einem Konto verknüpft, kein Tracking, keine Werbung. Was Apple selbst über die Systemeinstellungen sammelt, ist Apples Erhebung, nicht unsere. |
| Other Data | **Not Collected** | — |

**Tracking:** „Verwendest du Daten zur Nachverfolgung?“ → **Nein**. Kein
App-Tracking-Transparency-Prompt, `NSPrivacyTrackingDomains` ist leer.

**Drittanbieter-SDKs:** keine. Die App hat außer XcodeGen (Build-Zeit) keine
Abhängigkeiten; zur Laufzeit nur Apple-Frameworks (SwiftUI, CloudKit,
EventKit, AppIntents, WidgetKit, ActivityKit, UserNotifications,
AuthenticationServices, StoreKit).

**Privacy-Manifest:** `Haiity/PrivacyInfo.xcprivacy` liegt in **beiden**
Bundles (App und Widget-Extension — Apple prüft jedes Bundle einzeln,
ITMS-91053) und deklariert `NSPrivacyTracking=false`, leere
`NSPrivacyCollectedDataTypes` sowie eine einzige API-Nutzung:
`FileTimestamp` mit Grund `C617.1` (Änderungsdatum der eigenen `data.json`,
um nach einem Widget-Schreibvorgang neu zu laden).

---

## Offene Punkte vor dem Einreichen

- Support-URL und Datenschutz-URL sind in ASC Pflicht — Kandidaten:
  `https://aiity.de` bzw. die Datenschutzseite unter `site/haiity/`.
- IAP-Eintrag in ASC: `com.aiity.haiity.pro`, nicht-verbrauchbar,
  Familienfreigabe an. Anzeigename, Beschreibung und Review-Screenshot
  fehlen noch. Die lokale Testkonfiguration `Haiity.storekit` führt 9,99 €
  und Family Sharing — ASC muss denselben Stand bekommen, der Preis ist dort
  noch nicht gesetzt.
- Screenshots: 6.9" und 6.5" Pflicht. Naheliegende Reihenfolge — Raster,
  Habit-Arten, Statistik, Widgets/Sperrbildschirm, Einstellungen mit der
  „kein Server“-Zeile.
- Die App ist iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`, nur Hochformat),
  Ziel `MARKETING_VERSION 1.0.0`.

Erledigt: Kaufseite (`Haiity/Views/PaywallView.swift`) und alle sechs
Paywall-Stellen liegen im Build — ContentView (vierter Habit), MoreView
(hAiity-Pro-Zeile, eigene Farbe, Icon-Farbrad, Kalender) und StatsView. Der
Quell-Vertrag `ProGateTests` hält die Liste gegen den Code; die
Review-Notizen oben nennen dieselben sechs.
