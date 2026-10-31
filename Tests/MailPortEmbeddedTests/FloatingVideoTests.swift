import AppKit
import WebKit
import XCTest
import MailPortCore
@testable import MailPortEmbedded

final class FloatingVideoTests: XCTestCase {
    private func geometry() -> VideoFrame {
        VideoFrame(message: ["x": 100.0, "y": 100.0, "width": 640.0, "height": 360.0, "viewportWidth": 1000.0, "viewportHeight": 700.0])!
    }
    @MainActor func testDockMenuKeepsControlsBoundToTheirAccount() {
        let delegate = EmbeddedDelegate()
        let work = WorkspaceTab(accountID: UUID(), service: .youtube)
        let personal = WorkspaceTab(accountID: UUID(), service: .youtube)
        let menu = delegate.makeVideoDockMenu([
            (tab: work, label: "Work · Fixture", state: VideoPlaybackState(message: ["hasVideo": true, "playing": true]), poppedOut: false),
            (tab: personal, label: "Personal · Fixture", state: VideoPlaybackState(message: ["hasVideo": true, "playing": false]), poppedOut: true)
        ])
        XCTAssertEqual(menu.items.count, 2)
        let workControls = menu.items[0].submenu!
        let personalControls = menu.items[1].submenu!
        XCTAssertEqual(workControls.items[0].title, "Pause Video")
        XCTAssertEqual(personalControls.items[0].title, "Play Video")
        XCTAssertEqual(personalControls.items[1].title, "Return Video to Tab")
        XCTAssertTrue(workControls.items.allSatisfy { $0.representedObject as? String == work.id })
        XCTAssertTrue(personalControls.items.allSatisfy { $0.representedObject as? String == personal.id })
    }
    @MainActor func testLockCleanupRemovesTitlesFromAnAlreadyBuiltDockMenu() {
        let delegate = EmbeddedDelegate()
        let tab = WorkspaceTab(accountID: UUID(), service: .youtube)
        let menu = delegate.makeVideoDockMenu([(tab: tab, label: "Private fixture title", state: VideoPlaybackState(message: ["hasVideo": true]), poppedOut: false)])
        XCTAssertFalse(menu.items.isEmpty)
        delegate.clearVideoDockMenu()
        XCTAssertTrue(menu.items.isEmpty)
    }

    @MainActor func testCropMovesSameWebViewAndResizingPreservesItsViewport() {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), configuration: configuration)
        let originalHost = WebViewHost(webView: webView)
        let crop = VideoCropView(webView: webView, video: geometry())
        XCTAssertFalse(originalHost.subviews.contains(webView))
        XCTAssertTrue(webView.superview === crop)
        XCTAssertEqual(webView.frame, NSRect(x: -100, y: -100, width: 1000, height: 700))
        crop.setFrameSize(NSSize(width: 320, height: 180))
        XCTAssertEqual(crop.bounds.size, NSSize(width: 640, height: 360))
        XCTAssertEqual(webView.bounds.size, NSSize(width: 1000, height: 700))
    }
    @MainActor func testOpacityCompositesOnlyTheVideoAndLeavesControlsReadable() {
        let browser = BrowserTab(account: Account(name: "Fixture"), service: .youtube, store: .nonPersistent(), loadsInitialPage: false)
        browser.webView.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let controller = FloatingVideoController(browser: browser, frame: geometry(), screen: nil, opacity: 0.4)
        let content = controller.window!.contentView as! HoverVideoContentView
        XCTAssertEqual(content.crop.alphaValue, 0.4, accuracy: 0.001)
        XCTAssertEqual(content.alphaValue, 1)
        XCTAssertEqual(controller.window!.alphaValue, 1)
        content.setControlsVisible(true, animated: false)
        var saved: Double?
        controller.onOpacityChange = { saved = $0 }
        controller.setOpacity(0, notify: true)
        XCTAssertEqual(saved, 0.15)
        XCTAssertEqual(content.crop.alphaValue, 0.15, accuracy: 0.001)
        XCTAssertEqual(content.alphaValue, 1)
        controller.close()
        browser.discardForSecurity()
    }

    @MainActor func testHoverControlsDoNotResizeOrReparentTheVideo() {
        let browser = BrowserTab(account: Account(name: "Fixture"), service: .youtube, store: .nonPersistent(), loadsInitialPage: false)
        browser.webView.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let controller = FloatingVideoController(browser: browser, frame: geometry(), screen: nil)
        let content = controller.window!.contentView as! HoverVideoContentView
        XCTAssertFalse(controller.window!.styleMask.contains(.titled))
        XCTAssertTrue(controller.window!.styleMask.contains(.resizable))
        XCTAssertFalse(content.controlsVisible)
        let windowFrame = controller.window!.frame
        let viewport = browser.webView.bounds
        let parent = browser.webView.superview
        content.setControlsVisible(true, animated: false)
        XCTAssertTrue(content.controlsVisible)
        content.setControlsVisible(false, animated: false)
        XCTAssertFalse(content.controlsVisible)
        XCTAssertEqual(controller.window!.frame, windowFrame)
        XCTAssertEqual(browser.webView.bounds, viewport)
        XCTAssertTrue(browser.webView.superview === parent)
        content.updateTrackingAreas()
        XCTAssertTrue(content.trackingAreas.contains { $0.options.contains(.activeAlways) })
        controller.close()
        browser.discardForSecurity()
    }

    @MainActor func testFloatingWindowStaysAboveAppsAndReturnsPlayerExactlyOnce() {
        let browser = BrowserTab(account: Account(name: "Fixture"), service: .youtube, store: .nonPersistent(), loadsInitialPage: false)
        browser.webView.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let controller = FloatingVideoController(browser: browser, frame: geometry(), screen: nil)
        XCTAssertEqual(controller.window?.level, .floating)
        XCTAssertEqual((controller.window as? NSPanel)?.hidesOnDeactivate, false)
        XCTAssertTrue(controller.window?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        XCTAssertTrue(controller.window?.collectionBehavior.contains(.fullScreenAuxiliary) == true)
        var returns = 0
        controller.onReturn = { returns += 1 }
        controller.close(); controller.close()
        XCTAssertEqual(returns, 1)
        XCTAssertNil(browser.webView.superview)
        XCTAssertEqual(browser.webView.frame, NSRect(x: 0, y: 0, width: 1000, height: 700))
        let restored = WebViewHost(webView: browser.webView)
        XCTAssertTrue(browser.webView.superview === restored)
        browser.discardForSecurity()
    }
}
