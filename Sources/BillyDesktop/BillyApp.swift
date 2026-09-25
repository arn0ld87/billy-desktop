import AppKit

@main
@MainActor
enum BillyApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // kein Dock-Symbol, nur Menüleiste
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
