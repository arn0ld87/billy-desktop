# Echte Fotos von Billy einbauen

1. **Ziel:** Billy läuft mit fotorealistischen Bildern statt der Zeichnung über den Schreibtisch.
2. **Voraussetzungen:** ChatGPT mit Bildgenerierung, 2–4 gute Fotos von Billy (seitlich, ganzer Körper,
   gutes Licht), Python 3 auf dem Mac, Repo geklont.

## Schritt für Schritt

- Schritt 1: Neuen ChatGPT-Chat öffnen, Fotos anhängen und diesen Prompt senden:

```text
Das ist mein Hund Billy (Fotos anbei): schlanker, hochbeiniger Podenco-Mischling, weißes Fell
mit hellbraunen/orangen Platten auf Rücken, Hüfte und Ohren, große aufgestellte Ohren, hellbraune
Augenpartie mit weißer Blesse über Stirn und Schnauze, rosa-braune Nase, bernsteinfarbene Augen,
lange dünne weiße Rute.

Erstelle für eine Desktop-App eine Serie von Einzelbildern von Billy. Regeln für JEDES Bild:
- fotorealistisch, exakt dieser Hund, gleiche Fellzeichnung in jedem Bild
- reine Seitenansicht (Profil), Kopf zeigt nach RECHTS
- ganzer Hund sichtbar: Ohren, Pfoten und Rute nicht angeschnitten, etwas Rand drumherum
- transparenter Hintergrund (PNG); falls das nicht geht: einfarbig knallgrün #00FF00
- kein Boden, kein Schatten, kein Geschirr, kein Halsband, keine Leine
- gleiche Beleuchtung, gleiche Kamerahöhe, gleicher Maßstab in allen Bildern
- Querformat 1536×1024
Bestätige kurz und warte dann auf die erste Pose.
```

- Schritt 2: Im **selben Chat** je Pose einen Prompt senden und das Bild unter dem Dateinamen speichern:

| Datei | Prompt | Pflicht |
|---|---|---|
| `stand.png` | `Pose: Billy steht ruhig, alle vier Pfoten am Boden, Rute locker nach hinten, Blick nach rechts.` | ✅ |
| `walk_1.png` | `Pose: Billy geht im Schritt nach rechts, linkes Vorderbein weit vorne, rechtes Hinterbein vorne.` | empfohlen |
| `walk_2.png` | `Pose: gleicher Gang, Beine fast senkrecht unter dem Körper (Zwischenschritt).` | optional |
| `walk_3.png` | `Pose: gleicher Gang, rechtes Vorderbein weit vorne, linkes Hinterbein vorne.` | optional |
| `walk_4.png` | `Pose: gleicher Gang, Zwischenschritt wie walk_2, aber das andere Beinpaar vorne.` | optional |
| `carry.png` | `Pose: Billy geht nach rechts, Kopf erhoben, Maul leicht geöffnet, als würde er etwas Kleines tragen (Maul leer lassen).` | empfohlen |
| `sit.png` | `Pose: Billy sitzt aufrecht, Vorderbeine gerade, Blick nach rechts.` | empfohlen |
| `happy.png` | `Pose: Billy sitzt, Maul offen, Zunge leicht raus, fröhlicher Ausdruck.` | optional |
| `bark.png` | `Pose: Billy sitzt, Kopf leicht angehoben, Maul weit offen, er bellt.` | optional |
| `lie.png` | `Pose: Billy liegt wie eine Sphinx, Vorderbeine nach vorne gestreckt, Kopf aufrecht.` | empfohlen |
| `sleep.png` | `Pose: Billy liegt, Kopf auf den Vorderpfoten, Augen geschlossen, schläft.` | optional |
| `sniff.png` | `Pose: Billy steht, Nase tief am Boden, schnüffelt.` | empfohlen |

  Fehlende Posen ersetzt die App automatisch (z. B. `happy` → `sit`, `sleep` → `lie`). Mit nur einem
  Laufbild wippt Billy beim Laufen.

- Schritt 3 (Variante A, empfohlen): Bilder ins Repo hochladen – dann sind sie für alle Builds dabei
  - GitHub → Repo → Ordner `photos/` → **Add file → Upload files** → PNGs hineinziehen → Commit
  - danach im Repo-Ordner:
```bash
# stellt frei (KI-Maske, klappt auch auf weißem Hintergrund), skaliert, berechnet Maul/Nase
make photos-bundle && make install
```

- Schritt 3 (Variante B): nur lokal auf diesem Mac
```bash
mkdir -p ~/Pictures/Billy-Fotos   # PNGs hineinkopieren
make photos PHOTOS=~/Pictures/Billy-Fotos
```

- Schritt 4: Die App nimmt Fotos automatisch, sobald welche da sind. Umschalten:
  Menüleiste 🐾 → *Aussehen* → **Echte Fotos** / **Gezeichnet**

- Übersichtsbild mit mehreren Posen? Automatisch zerschneiden:
```bash
.venv/bin/python tools/photos/split_sheet.py uebersicht.png photos \
  --names walk_1,walk_2,walk_3,walk_4,carry,sit,happy,bark,lie,sleep,sniff
```

## Überprüfung

```bash
# sprites.json und PNGs müssen im Foto-Ordner der App liegen
ls ~/Library/Application\ Support/Billy\ Desktop/Sprites
# erwartet: sprites.json, stand_00.png, walk_00.png, …
```

Billy sagt „Tadaa – das bin ich in echt! 📸“.

## Probleme

| Problem | Lösung |
|---|---|
| Hund schaut nach links | `.venv/bin/python tools/photos/import_photos.py ~/Pictures/Billy-Fotos --flip sit.png` |
| Weißer Rand/Hintergrund bleibt | `make photos` installiert `rembg` (KI-Freistellung); notfalls Bild mit Greenscreen #00FF00 anfordern |
| Datei trägt er neben dem Maul | Anker in `sprites.json` (`mouth`, Punkte ab oben links, Frame 160×120) anpassen |
| Größen springen zwischen Posen | ChatGPT bitten: „gleicher Maßstab wie das Stand-Bild“ und neu erzeugen |

**Warum KI-Maske?** Billy ist überwiegend weiß. Eine einfache Farbauswahl frisst vor weißem
Hintergrund sein Fell weg. Die ISNet-Maske (rembg) erkennt den Hund als Objekt, die Farben
kommen unverändert aus dem Originalbild.

## Nächste Schritte

1. Zuerst nur `stand.png`, `walk_1.png` und `sit.png` erzeugen und testen
2. Danach die restlichen Posen ergänzen und erneut `make photos` ausführen
3. Wenn die Laufbilder uneinheitlich wirken: nur `walk_1.png` behalten (Billy wippt dann)
