# Zentrierte Root-Titel

## Ziel

`Habits`, `Statistik` und `Mehr` sollen denselben Titelaufbau verwenden. Der
Titel beginnt zentriert und groß im oberen Inhaltsbereich, bleibt frei von
Toolbar- und Kartenüberlappungen und schrumpft beim Scrollen in Richtung der
zentrierten nativen Navigation.

## Design

- Die drei Root-NavigationStacks behalten ihre native Navigation und Toolbar.
- Der native Titel wird inline zentriert dargestellt.
- Jede Root-Liste erhält einen eigenen scrollbaren Titelbereich vor dem ersten
  Inhalt. Die bestehende Listenbreite und Wallpaper-Schicht bleiben unverändert.
- Ein gemeinsamer, reiner Scrollfortschritt berechnet Größe, vertikalen Abstand
  und Sichtbarkeit des großen Titels. Bei reduziertem Bewegungseffekt wird nur
  zwischen den Zuständen überblendet.
- Unterseiten und Suchansicht behalten ihre bisherigen kompakten Titel.
- Es wird keine zweite Navigationsleiste und kein eigener Header-Hintergrund
  eingeführt.

## Verhalten

Der große Titel ist im Ruhezustand vollständig sichtbar und mittig. Beim
Hochscrollen wird er kleiner und zieht sich aus dem Inhaltsbereich zurück,
während der native Inline-Titel sichtbar bleibt. Der erste Kartenrand erhält
genügend Abstand, damit weder Titel noch Toolbar Inhalte verdecken.

## Prüfung

- Quellvertragstests prüfen die gemeinsame Root-Titel-Konfiguration für alle
  drei Seiten und den Inline-Navigationsmodus.
- Bestehende Navigations- und Darstellungstests bleiben grün.
- `git diff --check` und ein generischer iOS-Build werden ausgeführt.
