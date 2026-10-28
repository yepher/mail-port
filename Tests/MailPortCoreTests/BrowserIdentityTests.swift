import XCTest
@testable import MailPortCore

final class BrowserIdentityTests: XCTestCase {
    func testVerifiedAppleBuildsUseTheirConservativeReleaseBaseline() {
        let baselines = [
            "20624.1.16": "26.4",
            "20624.2.5": "26.5",
            "20624.3.9": "26.5",
            "20624.4.5": "26.6"
        ]
        for (build, version) in baselines {
            XCTAssertEqual(WebKitBrowserIdentity(engineBuild: build).safariCompatibilityVersion, version, build)
        }
    }

    func testKnownPlatformPrefixesShareTheVerifiedEngineBaseline() {
        for prefix in ["19624", "20624", "21624"] {
            XCTAssertEqual(WebKitBrowserIdentity(engineBuild: "\(prefix).1.16").safariCompatibilityVersion, "26.4")
            XCTAssertEqual(WebKitBrowserIdentity(engineBuild: "\(prefix).2.5").safariCompatibilityVersion, "26.5")
            XCTAssertEqual(WebKitBrowserIdentity(engineBuild: "\(prefix).4.5").safariCompatibilityVersion, "26.6")
        }
    }

    func testObservedRuntimeBuildKeepsLastVerifiedBaselineAndAppIdentity() {
        let identity = WebKitBrowserIdentity(engineBuild: "21624.5.1.11.3")
        XCTAssertEqual(identity.engineBuild, "21624.5.1.11.3")
        XCTAssertEqual(identity.safariCompatibilityVersion, "26.6")
        XCTAssertEqual(identity.applicationNameForUserAgent, "Version/26.6 Safari/605.1.15 MailPortPreview/0.2.1")
    }

    func testLaterRevisionsNeverClaimAnUnverifiedNewSafariRelease() {
        for build in ["20624.5.1", "21624.99.999", "19624.1000.1"] {
            let identity = WebKitBrowserIdentity(engineBuild: build)
            XCTAssertEqual(identity.safariCompatibilityVersion, "26.6", build)
            XCTAssertFalse(identity.applicationNameForUserAgent.contains("Version/27"), build)
        }
    }

    func testUnknownOrFutureEngineFamiliesDoNotInferACompatibilityVersion() {
        for build in [
            "20623.2.7", "20625.1.29", "21625.1.1", "20626.4.5",
            "22624.4.5", "18624.4.5", "624.4.5", "020624.4.5"
        ] {
            let identity = WebKitBrowserIdentity(engineBuild: build)
            XCTAssertNil(identity.safariCompatibilityVersion, build)
            XCTAssertEqual(identity.applicationNameForUserAgent, "MailPortPreview/0.2.1", build)
        }
    }

    func testMalformedOrIncompleteBuildsFailClosed() {
        for build in [
            "", "20624", "20624.", ".20624.4.5", "20624..4.5",
            "20624.4.5.", "20624.4.beta", "20624.4.5 build",
            " 20624.4.5", "20624.4.5\n", "20624.-4.5", "20624.+4.5",
            "20624.٤.5", "20624.999999999999999999999999999999.5", "20624.0.1"
        ] {
            let identity = WebKitBrowserIdentity(engineBuild: build)
            XCTAssertNil(identity.safariCompatibilityVersion, build)
            XCTAssertEqual(identity.applicationNameForUserAgent, "MailPortPreview/0.2.1", build)
        }
    }

    func testOnlyASuffixIsProducedAndMailPortIdentityIsAlwaysPresent() {
        for build in ["21624.5.1.11.3", "20625.1.29", "unknown"] {
            let suffix = WebKitBrowserIdentity(engineBuild: build, appVersion: "0.3.0").applicationNameForUserAgent
            XCTAssertTrue(suffix.hasSuffix("MailPortPreview/0.3.0"))
            XCTAssertFalse(suffix.contains("Chrome/"))
            XCTAssertFalse(suffix.contains("Mozilla/"))
            XCTAssertFalse(suffix.contains("AppleWebKit/"))
            XCTAssertFalse(suffix.contains("Macintosh"))
        }
    }
}
