import AppKit
import BillyCore

/// Billy räumt den Schreibtisch auf: planen, bestätigen lassen, Datei für Datei tragen.
@MainActor
final class TidyCoordinator {
    private weak var pet: PetController?
    private let fileManager = FileManager.default
    private let journalStore = JournalStore(url: Settings.supportDirectory.appendingPathComponent("last-tidy.json"))
    private(set) var isRunning = false

    /// So viele Dateien trägt Billy einzeln – den Rest erledigt er im Schnelldurchgang.
    private let maxAnimated = 12

    init(pet: PetController) {
        self.pet = pet
    }

    var desktopURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    var canUndo: Bool { !(journalStore.load()?.isEmpty ?? true) }

    // MARK: Aufräumen

    func start() {
        guard let pet, !isRunning else { return }
        let plan: TidyPlan
        do {
            plan = try makePlan()
        } catch {
            pet.say("Ich komm nicht an deinen Schreibtisch ran. Erlaubst du mir den Zugriff? 🥺")
            return
        }
        guard !plan.isEmpty else {
            pet.say(BillyReplies.tidySummary(moved: 0))
            return
        }
        guard confirm(plan) else {
            pet.say("Okay, dann eben nicht. 🐾")
            return
        }
        run(plan)
    }

    private func makePlan() throws -> TidyPlan {
        let urls = try fileManager.contentsOfDirectory(
            at: desktopURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let items = urls.map { url -> DesktopItem in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return DesktopItem(url: url, isDirectory: isDir)
        }
        return TidyPlanner.plan(items: items, desktop: desktopURL) { self.fileManager.fileExists(atPath: $0.path) }
    }

    private func confirm(_ plan: TidyPlan) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Billy möchte \(plan.moves.count) Dateien aufräumen"
        alert.informativeText = plan.summaryLines.map { "• " + $0 }.joined(separator: "\n")
            + "\n\nOrdner bleiben liegen, nichts wird gelöscht. Du kannst es jederzeit rückgängig machen."
        alert.addButton(withTitle: "Los, Billy!")
        alert.addButton(withTitle: "Abbrechen")
        if let icon = NSImage(named: NSImage.applicationIconName) { alert.icon = icon }
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func run(_ plan: TidyPlan) {
        guard let pet else { return }
        isRunning = true
        pet.interrupt()
        let executor = TidyExecutor(fileManager: fileManager)

        // Ordner zuerst anlegen und – falls der Finder mitspielt – in eine Spalte stellen.
        var folderSpots: [URL: CGPoint] = [:]
        let column = folderColumn(count: plan.folders.count)
        for (index, folder) in plan.folders.enumerated() {
            let existed = fileManager.fileExists(atPath: folder.path)
            try? executor.ensureFolder(folder)
            if !existed { DesktopIconLocator.setPosition(of: folder.lastPathComponent, to: column[index]) }
        }
        let icons = DesktopIconLocator.iconPositions() ?? [:]
        let finderOK = !icons.isEmpty
        for (index, folder) in plan.folders.enumerated() {
            folderSpots[folder] = icons[folder.lastPathComponent] ?? column[index]
        }

        var actions: [PetAction] = [.say(BillyReplies.random(for: .tidyDesktop))]
        if !finderOK {
            actions.append(.say("Ich darf den Finder nicht fragen, wo alles liegt – ich schätze einfach. 🐽"))
        }
        let animated = Array(plan.moves.prefix(maxAnimated))
        let rest = Array(plan.moves.dropFirst(maxAnimated))

        for move in animated {
            let fileSpot = icons[move.source.lastPathComponent] ?? pet.randomSpot()
            let folderSpot = folderSpots[move.folder] ?? pet.randomSpot()
            let iconImage = NSWorkspace.shared.icon(forFile: move.source.path)
            actions += carrySteps(move: move, from: fileSpot, to: folderSpot, icon: iconImage, executor: executor)
        }
        if !rest.isEmpty {
            actions.append(.run { [weak pet] in
                for move in rest { _ = try? executor.perform(move) }
                pet?.say("… und die restlichen \(rest.count) im Schnelldurchgang! 💨")
            })
            actions.append(.pose(.happy, duration: 1.5))
        }
        actions.append(.run { [weak self, weak pet] in
            guard let self else { return }
            try? self.journalStore.save(executor.journal)
            self.isRunning = false
            pet?.heart()
            pet?.say(BillyReplies.tidySummary(moved: executor.journal.records.count))
        })
        actions.append(.pose(.happy, duration: 2.5))
        pet.rest(.sit)
        pet.enqueue(actions)
    }

    /// Hinlaufen, schnüffeln, aufheben (= verschieben), zum Ordner tragen, ablegen.
    private func carrySteps(move: TidyMove, from fileSpot: CGPoint, to folderSpot: CGPoint,
                            icon: NSImage, executor: TidyExecutor) -> [PetAction] {
        guard let pet else { return [] }
        let approachLeft = fileSpot.x < pet.position.x
        let pickFeet = pet.clampToScreen(pet.feetPoint(placing: "nose", of: .sniff, at: fileSpot, faceLeft: approachLeft))
        let dropLeft = folderSpot.x < fileSpot.x
        let dropFeet = pet.clampToScreen(pet.feetPoint(placing: "mouth", of: .carry, at: folderSpot, faceLeft: dropLeft))
        var carried = false
        return [
            .walk(to: pickFeet, speed: 1.6, faceLeftOnArrival: approachLeft),
            .pose(.sniff, duration: 0.6),
            .run { [weak pet] in
                do {
                    try executor.perform(move)
                    carried = true
                    pet?.view.carriedIcon = icon
                } catch {
                    pet?.say("Hm, \(move.source.lastPathComponent) krieg ich nicht zu fassen.")
                }
            },
            .walk(to: dropFeet, speed: 1.6, carry: true, faceLeftOnArrival: dropLeft),
            .run { [weak pet] in
                if carried { pet?.view.carriedIcon = nil }
            },
        ]
    }

    /// Spalte für neue Ordner: zweite Reihe von rechts, oben beginnend.
    private func folderColumn(count: Int) -> [CGPoint] {
        let screen = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screen.maxX - 200
        return (0..<max(count, 1)).map { i in
            CGPoint(x: x, y: screen.maxY - 70 - CGFloat(i) * 100)
        }
    }

    // MARK: Rückgängig

    func undo() {
        guard let pet else { return }
        guard !isRunning else {
            pet.say("Moment, ich bin noch am Aufräumen! 🐾")
            return
        }
        guard let journal = journalStore.load(), !journal.isEmpty else {
            pet.say("Da gibt's nichts rückgängig zu machen. 🐶")
            return
        }
        let result = TidyExecutor.undo(journal, fileManager: fileManager)
        journalStore.clear()
        pet.interrupt()
        pet.enqueue([.pose(.happy, duration: 1.5)])
        if result.failed.isEmpty {
            pet.say("Alles zurückgelegt: \(result.restored) Dateien. 🐾")
        } else {
            pet.say("\(result.restored) zurückgelegt, \(result.failed.count) hab ich nicht mehr gefunden.")
        }
    }
}
