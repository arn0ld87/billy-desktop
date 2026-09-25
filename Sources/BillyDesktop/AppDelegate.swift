import AppKit
import BillyCore
import ServiceManagement

/// Menüleisten-Symbol, Befehle, Chat und Tastenkürzel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var pet: PetController?
    private var tidy: TidyCoordinator?
    private let chatModel = ChatModel()
    private lazy var chatPanel = ChatPanel(model: chatModel)
    private var hotKey: HotKey?
    private var chatHistory: [ClaudeClient.Turn] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        print("SELFTEST pet.visible=\(petVisible) chat.visible=\(chatPanel.isVisible) chat.frame=\(chat) "
              + "hotkey.registered=\(hotKey?.isRegistered ?? false)")
        exit(petVisible && chatOK ? 0 : 1)
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

        let claudeTitle = KeychainStore.apiKey == nil ? "Claude-Chat einrichten …" : "Claude-Schlüssel ändern …"
        menu.addItem(ActionItem(claudeTitle) { [weak self] in self?.configureClaude() })
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

    private func configureClaude() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Claude-Chat für Billy"
        alert.informativeText = """
        Optional: Mit einem Anthropic-API-Schlüssel versteht Billy auch freie Fragen. \
        Der Schlüssel liegt nur im Schlüsselbund dieses Macs. Befehle wie „Räum auf“ funktionieren auch ohne.
        """
        let field = NSSecureTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Speichern")
        alert.addButton(withTitle: "Abbrechen")
        alert.addButton(withTitle: "Schlüssel entfernen")
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            pet?.say(KeychainStore.save(key) ? "Jetzt kann ich richtig quatschen! 💬" : "Speichern hat nicht geklappt.")
        case .alertThirdButtonReturn:
            KeychainStore.delete()
            pet?.say("Schlüssel gelöscht.")
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
        guard let key = KeychainStore.apiKey else {
            let answer = BillyReplies.notUnderstood.randomElement()!
            chatModel.reply = answer
            pet?.say(answer)
            return
        }
        chatHistory.append(.init(role: "user", text: text))
        chatHistory = Array(chatHistory.suffix(12))
        if chatHistory.first?.role == "assistant" { chatHistory.removeFirst() }
        chatModel.isThinking = true
        let client = ClaudeClient(apiKey: key, model: Settings.shared.claudeModel)
        let history = chatHistory
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.chatModel.isThinking = false }
            do {
                let reply = try await client.send(history: history)
                let text = reply.text.isEmpty ? reply.command.map(BillyReplies.random(for:)) ?? "Wuff!" : reply.text
                self.chatHistory.append(.init(role: "assistant", text: text))
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
