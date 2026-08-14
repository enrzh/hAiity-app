import Combine
import SwiftUI
import UIKit

/// Schütteln — die Geste, mit der man auf dem iPhone seit jeher etwas
/// zurücknimmt und in TestFlight einen Fehler meldet.
///
/// **Warum die System-Geste und NICHT CoreMotion.** Ein Schütteln ist keine
/// Beschleunigung über einem selbst erfundenen Schwellwert. iOS erkennt es aus
/// dem Verlauf (Hin und Zurück, Dauer, Achse) und hat diese Abstimmung über
/// Jahre auf echten Händen gemacht — mit Gehen, Treppensteigen, Autofahrt und
/// einem Telefon in der Jackentasche. Ein eigener Zähler auf `CMMotionManager`
/// wäre die Wahl zwischen einem Blatt, das beim Joggen aufspringt, und einem,
/// das erst nach dem dritten Rütteln kommt. Dazu kostet das Abonnieren der
/// Bewegungsdaten dauerhaft Strom, während `motionEnded` erst dann überhaupt
/// etwas tut, wenn iOS bereits „das war ein Schütteln" gesagt hat.
///
/// **Warum eine Erweiterung von `UIWindow`.** Bewegungsereignisse laufen die
/// Antwortkette hinauf: vom ersten Antwortenden über seine Vorfahren bis zum
/// Fenster. Das Fenster ist der einzige Punkt, der IMMER darin liegt — egal ob
/// gerade ein Textfeld schreibt, ein Blatt offen ist oder überhaupt niemand
/// den Fokus hat. Ein eingehängter Ansichtscontroller (die Alternative) sieht
/// das Ereignis nur, solange er selbst in der Kette steht; genau beim Tippen
/// in ein Textfeld — der Moment, in dem etwas schiefgeht — wäre er es nicht.
///
/// **Warum das Ereignis nur MANCHMAL hier endet.** Wird aus dem Schütteln
/// wirklich ein Blatt, darf die Kette nicht weiterlaufen: Sonst käme über
/// dieselbe Geste zusätzlich das System-„Rückgängig?" hoch, und der Mensch
/// hätte zwei Fragen auf einmal auf dem Bildschirm. Passiert dagegen NICHTS
/// (abgeschaltet, es liegt schon etwas oben, die Hand wippt nach), gehört die
/// Geste wieder dem System — sonst wäre das Rückgängig-Schütteln in jedem
/// Textfeld der App dauerhaft tot, und wer „Schütteln zum Melden" ausschaltet,
/// bekäme dafür nicht etwa das Systemverhalten zurück, sondern gar nichts.
/// Deshalb geht die Quittung `ShakeClaim` mit hinaus und kommt beantwortet
/// zurück; jede andere Bewegung läuft ohnehin unverändert weiter.
///
/// **Warum eine Mitteilung und kein Rückruf.** Das Fenster gehört SwiftUI, wir
/// bekommen es nicht in die Hand. Die Mitteilung ist die eine Brücke von der
/// UIKit-Kette in die Ansichten — und `onShake` unten ist der einzige Ort, an
/// dem jemand sie abonnieren muss.
extension Notification.Name {
    static let haiityDeviceDidShake = Notification.Name("haiityDeviceDidShake")
}

/// Die Quittung für ein Schütteln: „ich habe daraus etwas gemacht".
///
/// **Warum ein Objekt und kein Rückgabewert.** Eine Mitteilung hat keinen
/// Rückweg — sie wird verschickt, nicht gefragt. Ein Verweistyp im Anhang ist
/// der Rückweg: Der Absender legt ihn bei, die Abonnenten hakt ihn ab, und
/// weil `NotificationCenter.post` die Abonnenten SYNCHRON bedient, steht die
/// Antwort fest, sobald `post` zurückkommt.
final class ShakeClaim {
    private(set) var isClaimed = false

    /// Einmal abgehakt bleibt abgehakt: Melden sich mehrere Abonnenten, reicht
    /// EINER, der die Geste verbraucht hat.
    func claim() { isClaimed = true }
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else {
            super.motionEnded(motion, with: event)
            return
        }
        let claim = ShakeClaim()
        NotificationCenter.default.post(name: .haiityDeviceDidShake, object: claim)
        guard claim.isClaimed else {
            // Niemand wollte sie: zurück in die Kette, dorthin, wo iOS sein
            // eigenes „Rückgängig?" anbietet.
            super.motionEnded(motion, with: event)
            return
        }
    }
}

extension View {
    /// Auf ein Schütteln hören — und melden, ob daraus etwas wurde.
    ///
    /// Bewusst dumm: dieser Baustein meldet nur, DASS geschüttelt wurde. Ob
    /// daraufhin etwas passieren soll, ob schon ein Blatt offen ist und wie
    /// lange nach dem Schliessen Ruhe herrscht, entscheidet die Ansicht, die
    /// das Blatt besitzt — sie ist die Einzige, die das weiss.
    ///
    /// **Warum die Handlung `Bool` zurückgibt.** Genau diese Ansicht weiss
    /// auch als Einzige, ob die Geste VERBRAUCHT wurde. `true` heisst „ein
    /// Blatt geht auf, das System bekommt sie nicht mehr", `false` gibt sie
    /// zurück an iOS (siehe die Quittung oben).
    func onShake(perform action: @escaping () -> Bool) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .haiityDeviceDidShake)) { note in
            guard action() else { return }
            (note.object as? ShakeClaim)?.claim()
        }
    }
}
