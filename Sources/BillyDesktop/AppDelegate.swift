import AppKit
import BillyCore
import ServiceManagement

/// Menüleisten-Symbol, Befehle, Chat und Tastenkürzel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var pet: PetController?
    private var tidy: TidyCoordinator?
    private lazy var sound = SoundPlayer()
    private let chatModel = ChatModel()
    private lazy var chatPanel = ChatPanel(model: chatModel)
    private var hotKey: HotKey?
    private var chatHistory: [ChatTurn] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        guard let sprites = SpriteLibrary.loadPreferred() else {
            let alert = NSAlert()
            alert.messageText = "Billys Bilder fehlen"
            alert.informativeText = "Resources/Sprites wurde nicht gefunden. Bitte die App mit scripts/build-app.sh bauen."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let pet = PetController(sprites: sprites)
        pet.onDoubleClick = { [weak self] in self?.openChat() }
        pet.menuProvider = { [weak self] in self?.buildMenu() }
        pet.onAnimationStart = { [weak self] animation, isReaction in
            guard let event = SoundPlayer.event(for: animation) else { return }
            self?.sound.play(event, isReaction: isReaction)
        }
        self.pet = pet
        tidy = TidyCoordinator(pet: pet)

        chatModel.onSubmit = { [weak self] text in self?.handleChat(text) }
        chatModel.onClose = { [weak self] in self?.chatPanel.orderOut(nil) }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Billy")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        hotKey = HotKey.billyDefault { [weak self] in
            Task { @MainActor in self?.toggleChat() }
        }

        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in await self.runSelfTest() }
        }
    }

    /// Startet die echte App, öffnet „Frag Billy“ und prüft, ob die Leiste sichtbar ist (für die CI).
    private func runSelfTest() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        openChat()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let chat = chatPanel.frame
        let petVisible = pet?.window.isVisible ?? false
        let chatOK = chatPanel.isVisible && chat.width >= 200 && chat.height >= 60
        let pasteOK = handlesKeyEquivalent("v")
        print("SELFTEST pet.visible=\(petVisible) chat.visible=\(chatPanel.isVisible) chat.frame=\(chat) "
              + "hotkey.registered=\(hotKey?.isRegistered ?? false) paste.shortcut=\(pasteOK)")
        exit(petVisible && chatOK && pasteOK ? 0 : 1)
    }

    /// Würde ⌘+Taste über das Hauptmenü an ein Textfeld weitergereicht?
    private func handlesKeyEquivalent(_ key: String) -> Bool {
        guard let menu = NSApp.mainMenu else { return false }
        return menu.items.contains { item in
            item.submenu?.items.contains { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command } ?? false
        }
    }

    /// Menüleisten-Apps haben kein Hauptmenü – ohne „Bearbeiten“-Menü laufen ⌘V/⌘C/⌘X/⌘A ins Leere.
    /// Das Menü ist unsichtbar, liefert Textfeldern (Schlüssel-Dialog, Chat) aber die Tastenkürzel.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Billy Desktop beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in buildMenu().items {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionItem("Frag Billy …  (⌃⌥B)") { [weak self] in self?.openChat() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("🧹 Schreibtisch aufräumen") { [weak self] in self?.runCommand(.tidyDesktop) })
        let undo = ActionItem("↩︎ Aufräumen rückgängig machen") { [weak self] in self?.runCommand(.undoTidy) }
        undo.isEnabled = tidy?.canUndo ?? false
        menu.addItem(undo)
        menu.addItem(.separator())

        let tricks: [(String, BillyCommand)] = [
            ("Sitz", .sit), ("Platz", .lieDown), ("Schlafen", .sleep), ("Komm her", .come),
            ("Gassi gehen", .walk), ("Gib Laut", .speak), ("Leckerli geben", .treat),
        ]
        let trickMenu = NSMenu()
        for (title, command) in tricks {
            trickMenu.addItem(ActionItem(title) { [weak self] in self?.runCommand(command) })
        }
        let trickItem = NSMenuItem(title: "🐾 Kommandos", action: nil, keyEquivalent: "")
        trickItem.submenu = trickMenu
        menu.addItem(trickItem)
        menu.addItem(.separator())

        let settings = Settings.shared
        let free = ActionItem("Frei herumlaufen") { [weak self] in
            settings.autonomous.toggle()
            self?.pet?.say(settings.autonomous ? "Juhu, Freilauf! 🎉" : "Okay, ich bleib hier.")
        }
        free.state = settings.autonomous ? .on : .off
        menu.addItem(free)

        let onTop = ActionItem("Immer im Vordergrund") { [weak self] in
            settings.alwaysOnTop.toggle()
            self?.pet?.applySettings()
        }
        onTop.state = settings.alwaysOnTop ? .on : .off
        menu.addItem(onTop)

        let sizeMenu = NSMenu()
        for (title, value) in [("Klein", 0.75), ("Mittel", 1.0), ("Groß", 1.4), ("Riesig", 2.0)] {
            let item = ActionItem(title) { [weak self] in
                settings.scale = CGFloat(value)
                self?.pet?.applySettings()
            }
            item.state = abs(settings.scale - CGFloat(value)) < 0.01 ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Größe", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let soundMenu = NSMenu()
        for (title, level) in [("Aus", SoundLevel.off), ("Nur Reaktionen", .reactions), ("Lebendig", .lively)] {
            let item = ActionItem(title) { [weak self] in
                settings.soundLevel = level
                self?.sound.applySettings()
            }
            item.state = settings.soundLevel == level ? .on : .off
            soundMenu.addItem(item)
        }
        soundMenu.addItem(.separator())
        soundMenu.addItem(SliderItem(title: "Lautstärke", value: settings.soundVolume) { [weak self] value in
            settings.soundVolume = value
            self?.sound.applySettings()
        })
        if !sound.hasSounds {
            let hint = NSMenuItem(title: "Keine Geräusche installiert – siehe docs/BILLY-TON.md", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            soundMenu.addItem(hint)
        }
        soundMenu.addItem(ActionItem("Geräusche-Ordner im Finder zeigen") { [weak self] in
            try? FileManager.default.createDirectory(at: Settings.soundsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([Settings.soundsDirectory])
            self?.sound.reload()
        })
        let soundItem = NSMenuItem(title: "Ton", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        let skinMenu = NSMenu()
        let drawn = ActionItem("Gezeichnet") { [weak self] in self?.switchSkin("drawn") }
        drawn.state = SpriteLibrary.isShowingPhotos ? .off : .on
        skinMenu.addItem(drawn)
        let photo = ActionItem("Echte Fotos") { [weak self] in self?.switchSkin("photo") }
        photo.state = SpriteLibrary.isShowingPhotos ? .on : .off
        photo.isEnabled = SpriteLibrary.hasPhotoSkin
        skinMenu.addItem(photo)
        skinMenu.addItem(ActionItem("Foto-Ordner im Finder zeigen") {
            try? FileManager.default.createDirectory(at: Settings.photoSpritesDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([Settings.photoSpritesDirectory])
        })
        let skinItem = NSMenuItem(title: "Aussehen", action: nil, keyEquivalent: "")
        skinItem.submenu = skinMenu
        menu.addItem(skinItem)

        let login = ActionItem("Beim Anmelden starten") { [weak self] in self?.toggleLoginItem() }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let aiMenu = NSMenu()
        let active = AIProvider.active
        let status = NSMenuItem(title: active.map { "Aktiv: \($0.title) (\($0.model))" } ?? "Kein KI-Schlüssel – nur Kommandos",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        aiMenu.addItem(status)
        aiMenu.addItem(.separator())
        for provider in AIProvider.allCases {
            let title = provider.apiKey == nil ? "\(provider.title)-Schlüssel hinterlegen …" : "\(provider.title)-Schlüssel ändern …"
            aiMenu.addItem(ActionItem(title) { [weak self] in self?.configureAI(provider) })
        }
        let aiItem = NSMenuItem(title: "KI-Chat", action: nil, keyEquivalent: "")
        aiItem.submenu = aiMenu
        menu.addItem(aiItem)
        menu.addItem(.separator())

        let visible = pet?.window.isVisible ?? true
        menu.addItem(ActionItem(visible ? "Billy verstecken" : "Billy zeigen") { [weak self] in
            guard let window = self?.pet?.window else { return }
            if window.isVisible { window.orderOut(nil) } else { window.orderFrontRegardless() }
        })
        menu.addItem(ActionItem("Beenden") { NSApp.terminate(nil) })
        return menu
    }

    private func switchSkin(_ skin: String) {
        Settings.shared.skin = skin
        if let library = SpriteLibrary.loadPreferred() {
            pet?.replaceSprites(library)
            pet?.say(skin == "photo" ? "Tadaa – das bin ich in echt! 📸" : "Wieder gezeichnet! ✏️")
        }
    }

    private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                pet?.say("Okay, ich komme nicht mehr automatisch.")
            } else {
                try SMAppService.mainApp.register()
                pet?.say("Ab jetzt bin ich nach dem Anmelden immer da! 🐾")
            }
        } catch {
            pet?.say("Das klappt nur, wenn ich als App in /Programme liege.")
        }
    }

    private func configureAI(_ provider: AIProvider) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(provider.title)-Chat für Billy"
        alert.informativeText = """
        Optional: Mit einem \(provider.title)-API-Schlüssel versteht Billy auch freie Fragen \
        (Modell: \(provider.model)). \(provider.keyHelp)

        Der Schlüssel liegt nur im Schlüsselbund dieses Macs. Befehle wie „Räum auf“ funktionieren auch ohne.
        """
        let field = NSSecureTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = provider.keyPlaceholder
        alert.accessoryView = field
        alert.addButton(withTitle: "Speichern")
        alert.addButton(withTitle: "Abbrechen")
        alert.addButton(withTitle: "Schlüssel entfernen")
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let saved = KeychainStore.save(key, account: provider.keychainAccount)
            chatHistory.removeAll()
            pet?.say(saved ? "Jetzt kann ich richtig quatschen! 💬" : "Speichern hat nicht geklappt.")
        case .alertThirdButtonReturn:
            KeychainStore.delete(account: provider.keychainAccount)
            chatHistory.removeAll()
            pet?.say("\(provider.title)-Schlüssel gelöscht.")
        default:
            break
        }
    }

    // MARK: Chat

    private func toggleChat() {
        if chatPanel.isVisible { chatPanel.orderOut(nil) } else { openChat() }
    }

    private func openChat() {
        guard let pet else { return }
        chatPanel.show(near: pet.windowFrame)
        pet.listen()
    }

    private func handleChat(_ text: String) {
        if let command = CommandParser.parse(text) {
            chatModel.reply = command == .help ? BillyReplies.helpText : nil
            runCommand(command)
            if command == .tidyDesktop || command == .undoTidy { chatPanel.orderOut(nil) }
            return
        }
        guard let client = AIProvider.active?.makeClient() else {
            let answer = BillyReplies.notUnderstood.randomElement()!
            chatModel.reply = answer
            pet?.say(answer)
            return
        }
        chatHistory.append(ChatTurn(role: .user, text: text))
        chatHistory = Array(chatHistory.suffix(12))
        if chatHistory.first?.role == .assistant { chatHistory.removeFirst() }
        chatModel.isThinking = true
        let history = chatHistory
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.chatModel.isThinking = false }
            do {
                let reply = try await client.send(history: history)
                let text = reply.text.isEmpty ? reply.command.map(BillyReplies.random(for:)) ?? "Wuff!" : reply.text
                self.chatHistory.append(ChatTurn(role: .assistant, text: text))
                self.chatModel.reply = text
                self.pet?.say(text)
                if let command = reply.command {
                    self.runCommand(command, announce: false)
                    if command == .tidyDesktop { self.chatPanel.orderOut(nil) }
                }
            } catch {
                self.chatHistory.removeLast()
                self.chatModel.reply = "🐶 " + error.localizedDescription
            }
        }
    }

    // MARK: Befehle

    func runCommand(_ command: BillyCommand, announce: Bool = true) {
        guard let pet, let tidy else { return }
        if announce, command != .tidyDesktop, command != .undoTidy {
            pet.say(BillyReplies.random(for: command))
        }
        switch command {
        case .tidyDesktop:
            tidy.start()
        case .undoTidy:
            tidy.undo()
        case .sit:
            pet.interrupt(); pet.rest(.sit)
        case .lieDown:
            pet.interrupt(); pet.rest(.lie)
        case .sleep:
            pet.interrupt(); pet.rest(.sleep)
        case .come:
            pet.interrupt()
            let mouse = NSEvent.mouseLocation
            let target = pet.clampToScreen(CGPoint(x: mouse.x, y: mouse.y - 40))
            let far = hypot(target.x - pet.position.x, target.y - pet.position.y) > 500
            pet.enqueue([.walk(to: target, speed: far ? 2.8 : 1.6), .play(.tilt)])
            pet.rest(.sit)
        case .walk:
            pet.interrupt()
            pet.enqueue((0..<3).map { _ in .walk(to: pet.randomSpot()) } + [.pose(.sniff, duration: 1.5)])
            pet.rest(.stand)
        case .speak:
            pet.interrupt()
            pet.enqueue([.pose(.bark, duration: 1.5)])
            pet.rest(.sit)
        case .treat:
            pet.interrupt(); pet.heart()
            pet.enqueue([.pose(.happy, duration: 2.5)])
            pet.rest(.sit)
        case .stay:
            pet.interrupt()
            Settings.shared.autonomous = false
            pet.rest(.sit)
        case .play:
            pet.interrupt()
            Settings.shared.autonomous = true
            pet.enqueue((0..<5).map { _ in .walk(to: pet.randomSpot(), speed: 2.8) } + [.play(.stretch), .pose(.hop, duration: 1.2)])
            pet.rest(.stand)
        case .hello:
            pet.heart()
            pet.enqueue([.pose(.hop, duration: 1.2)])
        case .help:
            pet.say(BillyReplies.helpText, seconds: 10)
        }
    }
}

/// Menüeintrag mit Closure statt Selector.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) wird nicht unterstützt")
    }

    @objc private func fire() {
        handler()
    }
}

/// Menüeintrag mit Schieberegler (0…1), z. B. für die Lautstärke.
final class SliderItem: NSMenuItem {
    private let onChange: (Double) -> Void

    init(title: String, value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(title: title, action: nil, keyEquivalent: "")
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 220, height: 30))
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.frame = CGRect(x: 20, y: 6, width: 80, height: 18)
        let slider = NSSlider(value: value, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.frame = CGRect(x: 100, y: 5, width: 108, height: 20)
        slider.target = self
        slider.action = #selector(changed(_:))
        container.addSubview(label)
        container.addSubview(slider)
        view = container
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) wird nicht unterstützt")
    }

    @objc private func changed(_ sender: NSSlider) {
        onChange(sender.doubleValue)
    }
}
