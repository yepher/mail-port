import AppKit
import Combine
import WebKit
import MailPortCore

/// Crops and scales the existing page natively; never edits the page or reloads it.
@MainActor
final class VideoCropView: NSView {
    private let cropSize: NSSize
    override var isFlipped: Bool { true }
    init(webView: WKWebView, video: VideoFrame) {
        let viewport = webView.bounds.size
        let scaleX = viewport.width / video.viewportWidth
        let scaleY = viewport.height / video.viewportHeight
        cropSize = NSSize(width: video.width * scaleX, height: video.height * scaleY)
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 480 * cropSize.height / cropSize.width))
        wantsLayer = true
        layer?.masksToBounds = true
        bounds = NSRect(origin: .zero, size: cropSize)
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = []
        webView.frame = NSRect(x: -video.x * scaleX, y: -video.y * scaleY, width: viewport.width, height: viewport.height)
        addSubview(webView)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        bounds = NSRect(origin: .zero, size: cropSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
private final class FloatingVideoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class VideoDragBar: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

@MainActor
private final class VideoDragTitle: NSTextField {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

@MainActor
private final class FloatingVideoButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class VideoResizeHandle: NSView {
    private var startFrame = NSRect.zero
    private var startPoint = NSPoint.zero
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1.5
        for inset in [5.0, 10.0] {
            lines.move(to: NSPoint(x: bounds.maxX - inset, y: 4))
            lines.line(to: NSPoint(x: bounds.maxX - 4, y: inset))
        }
        lines.stroke()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startPoint = NSEvent.mouseLocation
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, startFrame.height > 0 else { return }
        let aspect = startFrame.width / startFrame.height
        let deltaX = NSEvent.mouseLocation.x - startPoint.x
        let deltaY = (startPoint.y - NSEvent.mouseLocation.y) * aspect
        let delta = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        let visible = window.screen?.visibleFrame ?? startFrame
        let maximum = max(280, min(visible.width, visible.height * aspect))
        let width = min(maximum, max(window.contentMinSize.width, startFrame.width + delta))
        let height = width / aspect
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
    }
}

/// Hover chrome overlays the player, so revealing it never changes the video size.
@MainActor
final class HoverVideoContentView: NSView {
    let crop: VideoCropView
    private let header = VideoDragBar()
    private let resizeHandle = VideoResizeHandle()
    private var hoverTracking: NSTrackingArea?
    private var hoverTimer: Timer?
    private(set) var controlsVisible = false

    init(crop: VideoCropView, controls: NSView) {
        self.crop = crop
        super.init(frame: crop.frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(crop)
        header.material = .hudWindow
        header.blendingMode = .withinWindow
        header.state = .active
        header.appearance = NSAppearance(named: .vibrantDark)
        header.alphaValue = 0
        resizeHandle.alphaValue = 0
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
        layoutPlayer()
    }
    override func layout() { super.layout(); layoutPlayer() }
    private func layoutPlayer() {
        crop.frame = bounds
        header.frame = NSRect(x: 0, y: max(0, bounds.height - 32), width: bounds.width, height: 32)
        resizeHandle.frame = NSRect(x: max(0, bounds.width - 22), y: 0, width: 22, height: 22)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hoverTimer?.invalidate()
        hoverTimer = nil
        if window != nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
                // This timer is installed exclusively on the main run loop.
                MainActor.assumeIsolated {
                    guard let self else { timer.invalidate(); return }
                    self.refreshPointerState()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
            refreshPointerState()
        }
    }
    func refreshPointerState() {
        let inside = window.map { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) } ?? false
        if inside != controlsVisible { setControlsVisible(inside) }
    }
    override func mouseEntered(with event: NSEvent) { setControlsVisible(true) }
    override func mouseExited(with event: NSEvent) { setControlsVisible(false) }
    func setControlsVisible(_ visible: Bool, animated: Bool = true) {
        controlsVisible = visible
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                header.animator().alphaValue = visible ? 1 : 0
                resizeHandle.animator().alphaValue = visible ? 1 : 0
            }
        } else {
            header.alphaValue = visible ? 1 : 0
            resizeHandle.alphaValue = visible ? 1 : 0
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class FloatingVideoController: NSWindowController, NSWindowDelegate {
    let webView: WKWebView
    private let originalSize: NSSize
    private var returned = false
    var onReturn: (() -> Void)?
    var onToggle: (() -> Void)?
    var onFrameChange: ((NSRect) -> Void)?
    private let playButton = FloatingVideoButton()
    private var stateChanges: AnyCancellable?
    private let opacitySlider = NSSlider()
    private let opacityLabel = NSTextField(labelWithString: "100%")
    private(set) var opacity = 1.0
    var onOpacityChange: ((Double) -> Void)?

    init(browser: BrowserTab, frame: VideoFrame, screen: NSScreen?, opacity: Double = 1, savedFrame: NSRect? = nil) {
        webView = browser.webView
        originalSize = webView.bounds.size
        let crop = VideoCropView(webView: webView, video: frame)
        let panel = FloatingVideoPanel(contentRect: crop.frame, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "\(browser.account.name) · YouTube"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = crop.frame.size
        panel.contentMinSize = NSSize(width: 280, height: 280 * crop.frame.height / crop.frame.width)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        if let savedFrame, let restored = FloatingVideoPlacement.restore(savedFrame,
            aspect: crop.frame.width / crop.frame.height, screens: NSScreen.screens.map(\.visibleFrame), fallback: visible) {
            panel.setFrame(restored, display: false)
        } else {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.minY + 24))
        }
        super.init(window: panel)
        panel.delegate = self
        let close = FloatingVideoButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close floating video")!, target: self, action: #selector(returnVideo))
        close.toolTip = "Close floating window and return video to tab"
        let title = VideoDragTitle(labelWithString: panel.title)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .white
        title.alignment = .center
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        playButton.target = self; playButton.action = #selector(togglePlayback)
        let restore = FloatingVideoButton(image: NSImage(systemSymbolName: "pip.exit", accessibilityDescription: "Return video to tab")!, target: self, action: #selector(returnVideo))
        restore.toolTip = "Return video to its MailPort tab"
        for button in [close, playButton, restore] {
            button.bezelStyle = .inline
            button.isBordered = false
            button.contentTintColor = .white
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        opacitySlider.minValue = VideoOpacity.minimum * 100
        opacitySlider.maxValue = 100
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(changeOpacity)
        opacitySlider.setAccessibilityLabel("Video opacity")
        opacitySlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        opacityLabel.textColor = .white
        opacityLabel.alignment = .right
        opacityLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let controls = NSStackView(views: [close, title, playButton, restore, opacitySlider, opacityLabel])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6
        panel.contentView = HoverVideoContentView(crop: crop, controls: controls)
        setOpacity(opacity)
        updateButton(browser.videoPlayback.isPlaying)
        stateChanges = browser.$videoPlayback.sink { [weak self] state in self?.updateButton(state.isPlaying) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateButton(_ playing: Bool) {
        playButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: playing ? "Pause video" : "Play video")
        playButton.toolTip = playing ? "Pause video" : "Play video"
    }
    func setOpacity(_ value: Double, notify: Bool = false) {
        opacity = VideoOpacity.normalized(value)
        opacitySlider.doubleValue = opacity * 100
        opacityLabel.stringValue = "\(Int((opacity * 100).rounded()))%"
        opacitySlider.toolTip = "Video opacity: \(opacityLabel.stringValue)"
        // Keep the hover controls fully readable while the video becomes transparent.
        (window?.contentView as? HoverVideoContentView)?.crop.alphaValue = opacity
        if notify { onOpacityChange?(opacity) }
    }
    @objc private func changeOpacity() { setOpacity(opacitySlider.doubleValue / 100, notify: true) }

    @objc private func togglePlayback() { onToggle?() }
    @objc private func returnVideo() { close() }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() {
        guard !returned, let frame = window?.frame, FloatingVideoPlacement.isValid(frame) else { return }
        onFrameChange?(frame)
    }
    func windowWillClose(_ notification: Notification) { restore() }
    override func close() { restore(); super.close() }
    private func restore() {
        guard !returned else { return }
        saveFrame()
        returned = true
        stateChanges = nil
        webView.removeFromSuperview()
        webView.autoresizingMask = [.width, .height]
        webView.frame = NSRect(origin: .zero, size: originalSize)
        let callback = onReturn; onReturn = nil; onToggle = nil
        onOpacityChange = nil
        onFrameChange = nil
        callback?()
    }
}
