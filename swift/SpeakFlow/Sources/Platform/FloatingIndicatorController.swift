import AppKit
import Foundation

@MainActor
public final class FloatingIndicatorController {
    public enum State {
        case hidden
        case idle
        case recording(level: Float)
        case transcribing
        case done(String)
        case error(String)
    }

    private var hideDelay: TimeInterval
    private var hideTask: DispatchWorkItem?
    private let moveDelegate = PanelMoveDelegate()
    private let indicatorView = DictationIndicatorView()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 78, height: 78),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        moveDelegate.onMove = { [weak self] point in
            self?.onMoved?(point)
        }
        panel.delegate = moveDelegate

        let content = indicatorView
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 78),
            content.heightAnchor.constraint(equalToConstant: 78),
        ])
        panel.contentView = content

        return panel
    }()

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
                    x: screen.visibleFrame.maxX - frame.width - 22,
                    y: screen.visibleFrame.midY - (frame.height / 2)
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
        case .idle:
            indicatorView.update(state: .idle)
            show()
        case let .recording(level):
            indicatorView.update(state: .recording(level: level))
            show()
        case .transcribing:
            indicatorView.update(state: .transcribing)
            show()
        case let .done(message):
            indicatorView.update(state: .done(message))
            showThenIdle()
        case let .error(message):
            indicatorView.update(state: .error(message))
            showThenIdle()
        }
    }

    private func show() {
        panel.orderFrontRegardless()
    }

    private func showThenIdle() {
        show()
        let task = DispatchWorkItem { [weak self] in
            self?.indicatorView.update(state: .idle)
            self?.show()
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: task)
    }
}

private final class DictationIndicatorView: NSView {
    private var state: FloatingIndicatorController.State = .hidden
    private var level: Float = 0

    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func update(state: FloatingIndicatorController.State) {
        self.state = state
        if case let .recording(level) = state {
            self.level = min(max(level, 0), 1)
        } else {
            self.level = 0.36
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let circleRect = bounds.insetBy(dx: 7, dy: 7)
        let circle = NSBezierPath(ovalIn: circleRect)
        NSColor.black.withAlphaComponent(0.78).setFill()
        circle.fill()

        tintColor.withAlphaComponent(0.95).setStroke()
        circle.lineWidth = isRecording ? 3.4 : 2.8
        circle.stroke()

        switch state {
        case .error:
            drawSymbol("!", color: tintColor, in: circleRect)
        default:
            drawBars(in: circleRect)
        }
    }

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    private var tintColor: NSColor {
        switch state {
        case .recording:
            return .systemBlue
        case .transcribing:
            return .systemOrange
        case .done:
            return .systemGreen
        case .error:
            return .systemRed
        case .hidden, .idle:
            return .systemGray
        }
    }

    private func drawBars(in circleRect: NSRect) {
        let barWidth: CGFloat = 5
        let spacing: CGFloat = 9
        let centerX = circleRect.midX
        let centerY = circleRect.midY
        let normalizedLevel = CGFloat(min(max(level, 0.18), 1))
        let heights = [
            15 + normalizedLevel * 8,
            24 + normalizedLevel * 16,
            16 + normalizedLevel * 10
        ]
        let xPositions = [
            centerX - spacing - barWidth,
            centerX - (barWidth / 2),
            centerX + spacing
        ]

        tintColor.setFill()
        for index in 0..<3 {
            let rect = NSRect(
                x: xPositions[index],
                y: centerY - (heights[index] / 2),
                width: barWidth,
                height: heights[index]
            )
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    private func drawSymbol(_ symbol: String, color: NSColor, in circleRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: color
        ]
        let size = symbol.size(withAttributes: attributes)
        let point = NSPoint(
            x: circleRect.midX - size.width / 2,
            y: circleRect.midY - size.height / 2
        )
        symbol.draw(at: point, withAttributes: attributes)
    }
}

private final class PanelMoveDelegate: NSObject, NSWindowDelegate {
    var onMove: ((NSPoint) -> Void)?

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onMove?(window.frame.origin)
    }
}
