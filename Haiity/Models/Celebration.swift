import Foundation

/// Der Glückwunsch zum perfekten Tag: alle heute fälligen Habits erfüllt.
///
/// Die Botschaft ist LOKAL „generiert": ein kuratierter Pool aus Titeln und
/// Texten, deterministisch aus dem Tagesschlüssel gewürfelt — am selben Tag
/// stabil, am nächsten anders — und mit Namen, wenn der Nutzer einen
/// hinterlegt hat (Alias oder Apple-Anmeldung, siehe PersonalName). Kein
/// Server, kein Modell: die App verspricht Zero-Server, also entsteht die
/// Personalisierung aus Vorlagen auf dem Gerät.
///
/// Gefeiert wird EINMAL je Tag (`celebratedDay` in den App-Group-Defaults):
/// wer abhakt, zurücknimmt und wieder abhakt, bekommt keinen zweiten Banner
/// — und der Widget-Prozess sieht denselben Merker wie die App.
enum Celebration {
    static let celebratedKey = "celebratedDay"

    /// Ein perfekter Tag: mindestens ein Termin, und alle erfüllt. Ein
    /// beantwortetes „Nein" zählt bewusst NICHT — der Tag ist dann zwar
    /// abgeschlossen, aber nicht geschafft; ein Glückwunsch wäre gelogen.
    static func isPerfect(_ status: SummaryStatus) -> Bool {
        status.total > 0 && status.done == status.total
    }

    static func shouldCelebrate(status: SummaryStatus, today: String,
                                lastCelebrated: String?) -> Bool {
        isPerfect(status) && lastCelebrated != today
    }

    /// FNV-1a über den Tagesschlüssel: stabil über Prozesse hinweg (Swifts
    /// `hashValue` ist absichtlich je Lauf anders und taugt hier nicht).
    static func poolIndex(for dayKey: String, poolSize: Int) -> Int {
        guard poolSize > 0 else { return 0 }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in dayKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(poolSize))
    }

    /// Titel und Text des Glückwunschs. `name` = nil ⇒ neutrale Anrede.
    static func message(name: String?, today: String) -> (title: String, body: String) {
        let index = poolIndex(for: today, poolSize: bodies.count)
        let title: String
        if let name, !name.isEmpty {
            title = String(format: namedTitles[index], name)
        } else {
            title = plainTitles[index]
        }
        return (title, bodies[index])
    }

    // Die Pools sind gleich lang und laufen synchron: Index i wählt Titel
    // UND Text — so bleiben Tonlagen beieinander (ruhiger Titel, ruhiger
    // Text) statt zufällig gekreuzt.

    static let plainTitles: [String] = [
        String(localized: "Alle Habits geschafft!"),
        String(localized: "Tag komplett"),
        String(localized: "Sauber durchgezogen"),
        String(localized: "Volle Reihe"),
        String(localized: "Serie gepflegt"),
        String(localized: "Das war stark"),
    ]

    static let namedTitles: [String] = [
        String(localized: "%@, alle Habits geschafft!"),
        String(localized: "%@, Tag komplett"),
        String(localized: "Sauber durchgezogen, %@"),
        String(localized: "Volle Reihe, %@"),
        String(localized: "%@ bleibt dran"),
        String(localized: "Das war stark, %@"),
    ]

    static let bodies: [String] = [
        String(localized: "Alles von heute ist erledigt — das Raster leuchtet."),
        String(localized: "Jede Zelle von heute ist gefüllt. Morgen wartet die nächste Reihe."),
        String(localized: "Heute stand alles auf dem Plan — und alles ist drin."),
        String(localized: "Nichts offen geblieben. Das war ein guter Tag."),
        String(localized: "Komplett! Aus Tagen wie diesem bauen sich die Streaks."),
        String(localized: "Alle Habits von heute sitzen. Weiter so."),
    ]
}
