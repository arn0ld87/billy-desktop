# Billy Desktop – Kurzbefehle
APP := build/Billy Desktop.app
PHOTOS ?= $(HOME)/Pictures/Billy-Fotos

.PHONY: app run install test sprites photos venv clean

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

photos: venv    ## ChatGPT-Fotos importieren (PHOTOS=Ordner)
	.venv/bin/python tools/photos/import_photos.py "$(PHOTOS)"

clean:
	rm -rf .build build .venv
