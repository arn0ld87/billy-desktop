import AppKit
import SwiftUI

/// Zustand der „Frag Billy …“-Leiste.
@MainActor
final class ChatModel: ObservableObject {
    @Published var input = ""
    @Published var reply: String?
    @Published var isThinking = false
    @Published var focusToken = 0

    var onSubmit: ((String) -> Void)?
    var onClose: (() -> Void)?

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        input = ""
        onSubmit?(text)
    }
}

struct ChatView: View {
    @ObservedObject var model: ChatModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Exit") { model.onClose?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .foregroundColor(.white.opacity(0.8))
                Text("🐾 Billy")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if model.isThinking {
                    ProgressView().controlSize(.small).colorScheme(.dark)
                }
            }
            if let reply = model.reply {
                Text(reply)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                TextField("", text: $model.input, prompt: Text("Frag Billy …").foregroundColor(.white.opacity(0.45)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .focused($focused)
                    .onSubmit { model.submit() }
                Image(systemName: "return")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(16)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(red: 0.24, green: 0.18, blue: 0.22)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        )
        .padding(18)
        .onExitCommand { model.onClose?() }
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { _ in focused = true }
    }
}

/// Schwebendes Eingabefeld wie im Video: dunkle Leiste mit „Exit“.
final class ChatPanel: NSPanel {
    private(set) var model: ChatModel?

    convenience init(model: ChatModel) {
        self.init(contentRect: CGRect(x: 0, y: 0, width: 436, height: 140),
                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.model = model
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: ChatView(model: model))
        // Eigene Größe melden: sonst ist fittingSize 0×0 und die Leiste unsichtbar.
        // min/max lassen das Fenster mitwachsen, wenn Billys Antwort erscheint.
        hosting.sizingOptions = [.intrinsicContentSize, .minSize, .maxSize]
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    /// Zeigt die Leiste über (oder unter) Billy.
    func show(near petFrame: CGRect) {
        contentView?.layoutSubtreeIfNeeded()
        var size = contentView?.fittingSize ?? .zero
        if size.width < 200 || size.height < 60 {
            size = CGSize(width: 436, height: 120)   // Rückfall, falls SwiftUI noch keine Größe kennt
        }
        setContentSize(size)
        let screen = (NSScreen.screens.first { $0.frame.intersects(petFrame) } ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = CGPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY - 20)
        if origin.y + size.height > screen.maxY { origin.y = petFrame.minY - size.height }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        model?.focusToken += 1
    }
}
