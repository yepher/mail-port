import XCTest
@testable import MailPortCore

final class VideoPlaybackTests: XCTestCase {
    func testOpacityCannotMakeTheWindowInvisibleOrUseInvalidNumbers() {
        XCTAssertEqual(VideoOpacity.normalized(0), 0.15)
        XCTAssertEqual(VideoOpacity.normalized(2), 1)
        XCTAssertEqual(VideoOpacity.normalized(.nan), 1)
        XCTAssertEqual(VideoOpacity.normalized(0.45), 0.45)
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
