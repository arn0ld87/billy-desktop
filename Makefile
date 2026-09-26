# Billy Desktop – Kurzbefehle
APP := build/Billy Desktop.app
PHOTOS ?= $(HOME)/Pictures/Billy-Fotos
SOUNDS ?= $(HOME)/Downloads/Billy-Ton

.PHONY: app run install test sprites photos photos-bundle sounds sounds-bundle venv clean

app: ## .app bauen
	./scripts/build-app.sh

run: app        ## bauen und starten
	open "$(APP)"

install: app    ## nach /Applications kopieren und starten
	rm -rf "/Applications/Billy Desktop.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Billy Desktop.app"

test: ## Unit-Tests
	swift test

venv: ## Python-Umgebung für die Bild-Werkzeuge
	python3 -m venv .venv && .venv/bin/pip install -q -r tools/requirements.txt

sprites: venv   ## gezeichnete Sprites neu rendern
	.venv/bin/python tools/sprites/generate_sprites.py

photos: venv    ## eigene ChatGPT-Fotos importieren (PHOTOS=Ordner) → nur auf diesem Mac
	.venv/bin/pip install -q "rembg[cpu]"
	.venv/bin/python tools/photos/import_photos.py "$(PHOTOS)"

photos-bundle: venv ## Fotos aus photos/ als mitgeliefertes Aussehen bauen (Resources/PhotoSprites)
	.venv/bin/pip install -q "rembg[cpu]"
	.venv/bin/python tools/photos/import_photos.py photos --out Resources/PhotoSprites

sounds: ## eigene Geräusche importieren (SOUNDS=Ordner) → nur auf diesem Mac (braucht ffmpeg)
	python3 tools/sounds/import_sounds.py "$(SOUNDS)"

sounds-bundle: ## Geräusche aus sounds/ als mitgelieferten Ton bauen (Resources/Sounds)
	python3 tools/sounds/import_sounds.py sounds --out Resources/Sounds

clean:
	rm -rf .build build .venv
