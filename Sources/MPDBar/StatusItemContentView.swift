import AppKit

/// Keeps the playback symbol in place while only the song title moves.
final class StatusItemContentView: NSView {
    static let width: CGFloat = 165

    private let iconView = NSImageView()
    private let titleView = MarqueeTitleView(frame: NSRect(x: 31, y: 0, width: width - 38, height: 24))

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]

        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        addSubview(titleView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 7, y: (bounds.height - 18) / 2, width: 18, height: 18)
        titleView.frame = NSRect(x: 31, y: 0, width: max(0, bounds.width - 38), height: bounds.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // Let the status bar button receive clicks anywhere in the item.
    }

    func setIcon(_ image: NSImage?) {
        iconView.image = image
    }

    func setTitle(_ title: String) {
        titleView.setTitle(title)
    }
}

private final class MarqueeTitleView: NSView {
    private let scrollSpeed: CGFloat = 38 // Points per second.
    private let framesPerSecond: TimeInterval = 20
    private let gap = "     "
    private let font = NSFont.menuBarFont(ofSize: 0)
    private var title = ""
    private var cycleWidth: CGFloat = 0
    private var textHeight: CGFloat = 0
    private var scrollStart: TimeInterval = 0
    private var timer: Timer?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !title.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let text = title as NSString
        let y = floor((bounds.height - textHeight) / 2)
        let offset: CGFloat = timer == nil ? 0 : CGFloat(
            (ProcessInfo.processInfo.systemUptime - scrollStart) * Double(scrollSpeed)
        ).truncatingRemainder(dividingBy: cycleWidth)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        text.draw(at: NSPoint(x: -offset, y: y), withAttributes: attributes)
        if timer != nil {
            text.draw(at: NSPoint(x: cycleWidth - offset, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func setTitle(_ newTitle: String) {
        guard newTitle != title else { return }
        timer?.invalidate()
        timer = nil
        title = newTitle

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        textHeight = (newTitle as NSString).size(withAttributes: attributes).height
        let titleWidth = (newTitle as NSString).size(withAttributes: attributes).width
        cycleWidth = ((newTitle + gap) as NSString).size(withAttributes: attributes).width
        scrollStart = ProcessInfo.processInfo.systemUptime

        if titleWidth > bounds.width {
            let timer = Timer(timeInterval: 1.0 / framesPerSecond, target: self, selector: #selector(tick(_:)), userInfo: nil, repeats: true)
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        needsDisplay = true
    }

    @objc private func tick(_ timer: Timer) {
        needsDisplay = true
    }
}
