import XCTest
import CoreGraphics
@testable import MailPortCore

final class VideoPlaybackTests: XCTestCase {
    func testOpacityCannotMakeTheWindowInvisibleOrUseInvalidNumbers() {
        XCTAssertEqual(VideoOpacity.normalized(0), 0.15)
        XCTAssertEqual(VideoOpacity.normalized(2), 1)
        XCTAssertEqual(VideoOpacity.normalized(.nan), 1)
        XCTAssertEqual(VideoOpacity.normalized(0.45), 0.45)
    }
    func testFloatingPlacementRemembersPositionAndFitsChangedScreens() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = CGRect(x: 600, y: 250, width: 640, height: 360)
        XCTAssertEqual(FloatingVideoPlacement.restore(saved, aspect: 16 / 9, screens: [display], fallback: display), saved)
        let removedDisplay = CGRect(x: -1700, y: 120, width: 640, height: 360)
        let restored = FloatingVideoPlacement.restore(removedDisplay, aspect: 16 / 9, screens: [display], fallback: display)!
        XCTAssertTrue(display.contains(restored))
        XCTAssertEqual(restored.width, 640)
        let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(FloatingVideoPlacement.restore(removedDisplay, aspect: 16 / 9, screens: [secondary, display], fallback: display), removedDisplay)
        let portrait = FloatingVideoPlacement.restore(saved, aspect: 9 / 16, screens: [display], fallback: display)!
        XCTAssertTrue(display.contains(portrait))
        XCTAssertEqual(portrait.width / portrait.height, 9 / 16, accuracy: 0.001)
        XCTAssertNil(FloatingVideoPlacement.restore(CGRect(x: Double.nan, y: 0, width: 640, height: 360), aspect: 16 / 9, screens: [display], fallback: display))
    }

    func testPlaybackCannotBePlayingWithoutAVideo() {
        XCTAssertFalse(VideoPlaybackState(message: ["playing": true]).isPlaying)
        XCTAssertTrue(VideoPlaybackState(message: ["hasVideo": true, "playing": true]).isPlaying)
        XCTAssertFalse(VideoPlaybackState.none.hasVideo)
    }
    func testUntrustedCropGeometryMustStayWithinViewport() {
        let valid: [String: Any] = ["x": 100.0, "y": 100.0, "width": 640.0, "height": 360.0, "viewportWidth": 1000.0, "viewportHeight": 700.0]
        XCTAssertNotNil(VideoFrame(message: valid))
        for (key, value) in [("x", -30.0), ("width", 10000.0), ("height", Double.nan), ("viewportWidth", 0.0), ("y", Double.infinity)] {
            var invalid = valid; invalid[key] = value
            XCTAssertNil(VideoFrame(message: invalid))
        }
    }
}
