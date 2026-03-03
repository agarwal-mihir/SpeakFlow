import AppKit
import Foundation

@MainActor
public final class FloatingIndicatorController {
    public enum State {
        case hidden
        case recording(level: Float)
        case transcribing
        case done(String)
        case error(String)
    }

    private var hideDelay: TimeInterval
    private var hideTask: DispatchWorkItem?
    private let moveDelegate = PanelMoveDelegate()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 62),
            styleMask: [.nonactivatingPanel, .titled],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        moveDelegate.onMove = { [weak self] point in
            self?.onMoved?(point)
        }
        panel.delegate = moveDelegate

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        meter.isIndeterminate = false
        meter.minValue = 0
        meter.maxValue = 1
        meter.doubleValue = 0

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(meter)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        panel.contentView = content

        return panel
    }()

    private let label = NSTextField(labelWithString: "Idle")
    private let meter = NSProgressIndicator()
    public var onMoved: ((NSPoint) -> Void)?

    public init(hideDelayMs: Int) {
        self.hideDelay = TimeInterval(max(hideDelayMs, 200)) / 1000.0
    }

    public func setHideDelayMs(_ hideDelayMs: Int) {
        hideDelay = TimeInterval(max(hideDelayMs, 200)) / 1000.0
    }

    public func setPosition(x: Double?, y: Double?) {
        if let x, let y {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            if let screen = NSScreen.main {
                let frame = panel.frame
                let origin = NSPoint(
                    x: screen.visibleFrame.midX - (frame.width / 2),
                    y: screen.visibleFrame.minY + 56
                )
                panel.setFrameOrigin(origin)
            }
        }
    }

    public func currentOrigin() -> NSPoint {
        panel.frame.origin
    }

    public func update(state: State) {
        hideTask?.cancel()
        hideTask = nil

        switch state {
        case .hidden:
            panel.orderOut(nil)
        case let .recording(level):
            label.stringValue = "Recording"
            meter.doubleValue = Double(level)
            show()
        case .transcribing:
            label.stringValue = "Transcribing"
            meter.doubleValue = 0
            show()
        case let .done(message):
            label.stringValue = message
            meter.doubleValue = 0
            showThenHide()
        case let .error(message):
            label.stringValue = message
            meter.doubleValue = 0
            showThenHide()
        }
    }

    private func show() {
        panel.orderFront(nil)
    }

    private func showThenHide() {
        show()
        let task = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: task)
    }
}

private final class PanelMoveDelegate: NSObject, NSWindowDelegate {
    var onMove: ((NSPoint) -> Void)?

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onMove?(window.frame.origin)
    }
}
