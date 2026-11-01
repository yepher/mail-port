import AppKit
import WebKit
import MailPortCore

/// A key window without a title bar, so a detached page can still take typing.
@MainActor
private final class DetachedWindow: NSWindow {
    var onTogglePin: (() -> Void)?
    var onReload: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// These would otherwise reach the menu bar and act on the main window's selection.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "w" { close(); return true }
        if modifiers == .command, key == "r" { onReload?(); return true }
        if modifiers == [.command, .control], key == "p" { onTogglePin?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class DetachedResizeHandle: NSView {
    private var startFrame = NSRect.zero
    private var startPoint = NSPoint.zero
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1.5
        for inset in [5.0, 10.0] {
            lines.move(to: NSPoint(x: bounds.maxX - inset, y: 4))
            lines.line(to: NSPoint(x: bounds.maxX - 4, y: inset))
        }
        lines.stroke()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startPoint = NSEvent.mouseLocation
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let width = max(window.minSize.width, startFrame.width + NSEvent.mouseLocation.x - startPoint.x)
        let height = max(window.minSize.height, startFrame.height + startPoint.y - NSEvent.mouseLocation.y)
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
    }
}

/// The page fills the window. Controls overlay it only while the pointer is at the
/// top edge, so they never sit on top of the page's own toolbar while it's in use.
@MainActor
final class DetachedContentView: NSView {
    static let revealDepth: CGFloat = 8
    static let headerHeight: CGFloat = 32
    private let webView: WKWebView
    private let header = VideoDragBar()
    private let resizeHandle = DetachedResizeHandle()
    private var pointerTimer: Timer?
    private(set) var controlsVisible = false

    init(frame: NSRect, webView: WKWebView, controls: NSView) {
        self.webView = webView
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        addSubview(webView)
        header.material = .hudWindow
        header.blendingMode = .withinWindow
        header.state = .active
        header.alphaValue = 0
        header.isHidden = true
        resizeHandle.alphaValue = 0.6
        addSubview(header)
        addSubview(resizeHandle)
        controls.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            controls.topAnchor.constraint(equalTo: header.topAnchor),
            controls.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])
        layoutChrome()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() { super.layout(); layoutChrome() }
    private func layoutChrome() {
        header.frame = NSRect(x: 0, y: max(0, bounds.height - Self.headerHeight), width: bounds.width, height: Self.headerHeight)
        resizeHandle.frame = NSRect(x: max(0, bounds.width - 18), y: 0, width: 18, height: 18)
    }

    /// Kept open once revealed, so moving from the edge onto the controls doesn't hide them.
    static func showsControls(pointer: NSPoint, window: NSRect, visible: Bool) -> Bool {
        window.contains(pointer) && window.maxY - pointer.y <= (visible ? headerHeight : revealDepth)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pointerTimer?.invalidate()
        pointerTimer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            // Installed exclusively on the main run loop.
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.refreshPointerState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func refreshPointerState() {
        guard let window, window.isVisible else { return }
        let show = Self.showsControls(pointer: NSEvent.mouseLocation, window: window.frame, visible: controlsVisible)
        if show != controlsVisible { setControlsVisible(show) }
    }

    func setControlsVisible(_ visible: Bool) {
        controlsVisible = visible
        header.isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            header.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.controlsVisible == false { self?.header.isHidden = true } }
        })
    }
}

/// Shows one view's existing page in its own borderless window. The same web view
/// moves here and back, so nothing reloads and the account's session stays put.
@MainActor
final class DetachedViewController: NSWindowController, NSWindowDelegate {
    static let defaultSize = NSSize(width: 900, height: 640)
    let tab: WorkspaceTab
    private let webView: WKWebView
    private let pinButton = FloatingVideoButton()
    private var returned = false
    private(set) var isPinned: Bool
    var onReturn: (() -> Void)?
    var onFrameChange: ((NSRect) -> Void)?
    var onPinChange: ((Bool) -> Void)?

    init(tab: WorkspaceTab, browser: BrowserTab, title: String, frame: NSRect, pinned: Bool) {
        self.tab = tab
        webView = browser.webView
        isPinned = pinned
        let window = DetachedWindow(contentRect: frame, styleMask: [.borderless, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = NSSize(width: 360, height: 280)
        super.init(window: window)
        window.delegate = self
        window.onTogglePin = { [weak self] in self?.togglePin() }
        window.onReload = { [weak browser] in browser?.reload() }
        let close = FloatingVideoButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Return to the main window")!, target: self, action: #selector(returnToTab))
        close.toolTip = "Return to the main window (⌘W)"
        let label = VideoDragTitle(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        for button in [close, pinButton] {
            button.bezelStyle = .inline
            button.isBordered = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let controls = NSStackView(views: [close, label, pinButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6
        window.contentView = DetachedContentView(frame: NSRect(origin: .zero, size: frame.size), webView: webView, controls: controls)
        applyPin()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A saved frame is used only if part of it is still on a connected screen.
    static func placement(saved: NSRect?, screens: [NSRect], fallback: NSRect) -> NSRect {
        if let saved, saved.width >= 360, saved.height >= 280,
           screens.contains(where: { $0.intersection(saved).width >= 100 && $0.intersection(saved).height >= 100 }) { return saved }
        let width = min(defaultSize.width, fallback.width), height = min(defaultSize.height, fallback.height)
        return NSRect(x: fallback.midX - width / 2, y: fallback.midY - height / 2, width: width, height: height)
    }

    private func applyPin() {
        window?.level = isPinned ? .floating : .normal
        window?.collectionBehavior = isPinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        pinButton.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: isPinned ? "Stop keeping on top" : "Keep on top")
        pinButton.toolTip = isPinned ? "Stop keeping on top of other windows (⌃⌘P)" : "Keep on top of other windows (⌃⌘P)"
    }

    @objc func togglePin() {
        isPinned.toggle()
        applyPin()
        onPinChange?(isPinned)
    }

    @objc private func returnToTab() { close() }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() { if !returned, let frame = window?.frame { onFrameChange?(frame) } }
    func windowWillClose(_ notification: Notification) { restore() }
    override func close() { restore(); super.close() }

    private func restore() {
        guard !returned else { return }
        saveFrame()
        returned = true
        webView.removeFromSuperview()
        webView.autoresizingMask = [.width, .height]
        let callback = onReturn
        onReturn = nil; onFrameChange = nil; onPinChange = nil
        (window as? DetachedWindow)?.onTogglePin = nil
        (window as? DetachedWindow)?.onReload = nil
        callback?()
    }
}
