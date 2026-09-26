# Billy bekommt Ton

1. **Ziel:** Billy bellt, hechelt, winselt und schnarcht – leise und nie in einen Call hinein.
2. **Voraussetzungen:** kostenloser Account bei [freesound.org](https://freesound.org), `ffmpeg`
   (`brew install ffmpeg`), Repo geklont.

## Was Billy wann macht

| Datei | Geräusch | Wann |
|---|---|---|
| `bark` | kurzes Bellen | „Gib Laut“ |
| `happy` | fröhliches Kläffen/Fiepen | Kraulen, Leckerli, Hallo |
| `whine` | Winseln | beim Hochheben mit der Maus |
| `sniff` | Schnüffeln | Aufräumen (Datei beschnuppern) |
| `drop` | leises „Plopp“ | Datei landet im Ordner |
| `yawn` | Gähnen | Strecken nach dem Aufwachen |
| `pant` | Hecheln | Galopp (Zoomies) |
| `snore` | Schnarchen | beim Schlafen |

Menüleiste 🐾 → **Ton**:
- **Aus**: stumm
- **Nur Reaktionen**: Geräusche nur, wenn du mit Billy etwas machst
- **Lebendig** (Standard): zusätzlich von selbst, aber mit etwa ⅓ Lautstärke und höchstens alle 2½ Minuten

Solange das Mikrofon benutzt wird (Call, Aufnahme), ist Billy immer still.

## Schritt für Schritt

- Schritt 1: Auf freesound.org je Geräusch suchen, **nur mit Lizenzfilter „Creative Commons 0“**
  (Suchseite → Filter *License* → *Creative Commons 0*). Suchbegriffe:

| Datei | Suchbegriff |
|---|---|
| `bark.wav` | `small dog bark single` |
| `happy.wav` | `dog whimper happy` oder `puppy yip` |
| `whine.wav` | `dog whine` |
| `sniff.wav` | `dog sniffing` |
| `drop.wav` | `soft pop` oder `paper drop` |
| `yawn.wav` | `dog yawn` |
| `pant.wav` | `dog panting` |
| `snore.wav` | `dog snoring` |

  Kurze, trockene Aufnahmen ohne Hall und ohne Hintergrundlärm sind am besten. Mehrere Varianten
  sind erlaubt (`bark_1.wav`, `bark_2.wav` …) – Billy wählt dann zufällig.

- Schritt 2: Dateien umbenennen und in den Ordner `sounds/` im Repo legen. Dazu eine
  `sounds/CREDITS.md` mit Quelle und Lizenz je Datei:
```markdown
| Datei | Quelle | Urheber | Lizenz |
|---|---|---|---|
| bark_1.wav | https://freesound.org/s/12345/ | nutzername | CC0 |
```

- Schritt 3: Zuschneiden, Lautstärke angleichen, einbauen:
```bash
# kürzt, entfernt Stille, gleicht Lautheit an → Resources/Sounds/*.m4a
make sounds-bundle && make install
```

  Nur für diesen Mac, ohne Repo: `make sounds SOUNDS=~/Downloads/Billy-Ton`
  (landet in `~/Library/Application Support/Billy Desktop/Sounds` und hat Vorrang).

## Überprüfung

```bash
ls Resources/Sounds
# erwartet: bark_00.m4a, happy_00.m4a, …, CREDITS.md
```

Menüleiste 🐾 → *Kommandos* → *Gib Laut* → Billy bellt.

## Probleme

| Problem | Lösung |
|---|---|
| Billy bleibt stumm | Menü *Ton* auf *Lebendig*, Lautstärke hoch; läuft ein Call/Mikrofon? |
| Menü zeigt „Keine Geräusche installiert“ | `ls Resources/Sounds` prüfen, danach `make install` |
| Ein Geräusch ist zu lang oder abgeschnitten | Grenzen in `tools/sounds/import_sounds.py` (`MAX_SECONDS`) anpassen |
| Ein Geräusch ist zu laut | `LOUDNESS` im Werkzeug senken (z. B. −24 statt −20) |

**Warum CC0?** CC0-Geräusche dürfen ohne Namensnennung mitgeliefert werden. Die `CREDITS.md`
führen wir trotzdem – aus Fairness und damit jederzeit klar ist, woher ein Geräusch stammt.
