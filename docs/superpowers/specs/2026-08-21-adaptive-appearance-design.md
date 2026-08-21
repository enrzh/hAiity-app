# Selbstanpassende Darstellung Design

## Ziel

`Darstellung` bekommt eine vierte Oberflächenoption namens `Selbstanpassend`. Sie
leitet Oberflächen-Tönung, Lesbarkeits-Scrim und Raster-Kontrast aus dem bereits
gewählten Hintergrund ab, ohne die vom Nutzer gewählte Habit- oder GitHub-
Farbpalette zu ersetzen.

## Design

`AppearanceMaterial.adaptive` bleibt Teil von `AppearancePreferences`, damit
die bestehende Darstellungseinstellung weiterhin die einzige Quelle für
Material und Hintergrund bleibt. Die Codable-Darstellung schreibt zusätzlich
ein kompatibles `adaptive`-Merkmal neben dem bisherigen `material`-Wert; ältere
Builds sehen deshalb weiterhin `solid`, statt an einem unbekannten Enum-Wert zu
scheitern. Neue Builds lesen dieses Merkmal wieder als `adaptive`.

Eine gemeinsame `AdaptiveAppearance`-Berechnung in `Theme.swift` bestimmt eine
Referenzfarbe: der gewählte Farb-Hintergrund direkt, beim Verlauf der Mittelwert
der beiden Endfarben und beim Bild ein kleiner, günstiger Durchschnittssample
mit System-Hintergrund als Fallback. Daraus werden Helligkeit, Akzent-Tönung,
Oberflächen-Overlay und der passende Hintergrund-Scrim abgeleitet. Die
Darstellung bleibt auf iOS 26 bei `glassEffect` und fällt auf älteren Systemen
auf Material mit derselben Tönung zurück.

`GitHubContributionGraph` liest die vorhandenen Appearance Preferences aus der
Umgebung. Nur im selbstanpassenden Modus wird die bestehende Palette so weit
gegen den Hintergrund verschoben, dass leere und gefüllte Kacheln sichtbar
bleiben; Hue und semantische Level-Reihenfolge bleiben erhalten. Zusätzlich
erhalten die Kacheln in diesem Modus eine sehr feine kontrastierende Kontur.
Widget-Code und die gespeicherte Palette bleiben unverändert.

## UI und Persistenz

- `Oberfläche` zeigt automatisch `Solid`, `Milchglas`, `Liquid Glass` und
  `Selbstanpassend`.
- Hintergrundauswahl, App-Icon-Kopplung und Graph-Palette behalten ihr bisheriges
  Verhalten.
- Der neue Modus speichert keine abgeleiteten Farben. Dadurch aktualisiert er
  sich automatisch, wenn der Nutzer später Farbe, Verlauf oder Bild ändert und
  reist korrekt über den bestehenden iCloud-Payload.
- Neue sichtbare Texte werden mit `String(localized:)` angelegt und in
  `Localizable.xcstrings` ergänzt.

## Verification

- Codable-Roundtrip und Legacy-Fallback für den neuen Modus.
- Reine Kontrasttests für helle, dunkle, Farb- und Verlaufshintergründe.
- Source-/View-Vertrag für den neuen Pickerwert und die adaptive GitHub-
  Palette/Kontur.
- Simulator-Screenshots der Darstellung und GitHub-Karte mit solid, gradient
  und image backgrounds in hellem und dunklem Farbschema. Kein Release- oder
  TestFlight-Upload in diesem Änderungsschritt.
