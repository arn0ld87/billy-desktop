import AVFoundation
import BillyCore
import CoreAudio

/// Spielt Billys Geräusche aus `Sounds/` (eigene im Support-Ordner haben Vorrang vor den mitgelieferten).
/// Fehlt eine Datei, bleibt Billy an dieser Stelle einfach still.
@MainActor
final class SoundPlayer {
    static let fileExtensions: Set<String> = ["m4a", "wav", "aiff", "aif", "caf", "mp3"]

    private var files: [SoundEvent: [URL]] = [:]
    private var playing: [AVAudioPlayer] = []
    private var policy: SoundPolicy

    init() {
        policy = SoundPolicy(level: Settings.shared.soundLevel, volume: Float(Settings.shared.soundVolume))
        reload()
    }

    var hasSounds: Bool { !files.isEmpty }

    func reload() {
        files = [:]
        for dir in [Self.bundledDirectory(), Settings.soundsDirectory].compactMap({ $0 }) {
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            var found: [SoundEvent: [URL]] = [:]
            for url in urls where Self.fileExtensions.contains(url.pathExtension.lowercased()) {
                let base = url.deletingPathExtension().lastPathComponent.lowercased()
                let name = base.split(separator: "_").first.map(String.init) ?? base
                if let event = SoundEvent(rawValue: name) { found[event, default: []].append(url) }
            }
            files.merge(found) { _, own in own }   // eigene ersetzen mitgelieferte je Geräusch
        }
    }

    func applySettings() {
        policy.level = Settings.shared.soundLevel
        policy.volume = Float(Settings.shared.soundVolume)
    }

    func play(_ event: SoundEvent, isReaction: Bool) {
        guard let url = files[event]?.randomElement() else { return }
        guard let volume = policy.volume(for: event, isReaction: isReaction,
                                          microphoneInUse: MicrophoneMonitor.isInUse) else { return }
        playing.removeAll { !$0.isPlaying }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = volume
        player.play()
        playing.append(player)
    }

    /// Welches Geräusch gehört zum Beginn dieser Animation?
    static func event(for animation: Animation) -> SoundEvent? {
        switch animation {
        case .bark: return .bark
        case .happy, .hop: return .happy
        case .run: return .pant
        case .dangle: return .whine
        case .sleep: return .snore
        case .sniff, .pick: return .sniff
        case .stretch: return .yawn
        case .place: return .drop
        default: return nil
        }
    }

    /// `Resources/Sounds` im App-Bundle oder – bei `swift run` – im Repo.
    static func bundledDirectory() -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Sounds"),
           fm.fileExists(atPath: res.path) {
            return res
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/Sounds")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}

/// Erkennt per CoreAudio, ob irgendeine App gerade das Mikrofon nutzt (Call, Aufnahme).
/// Braucht keine Mikrofon-Freigabe, weil nur der Gerätestatus gelesen wird.
enum MicrophoneMonitor {
    static var isInUse: Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
