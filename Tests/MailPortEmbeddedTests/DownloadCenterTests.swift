import Foundation
import XCTest
@testable import MailPortEmbedded

final class DownloadCenterTests: XCTestCase {
    @MainActor func testCancellationWinsAgainstLateCompletionAndRetrySurvivesFailure() {
        let center = DownloadCenter(); var cancellations = 0; var retries = 0
        let id = center.begin(account: "Fixture", source: "YouTube", destination: URL(fileURLWithPath: "/tmp/fixture.mp4"), cancel: { cancellations += 1 }, retry: { retries += 1 })
        center.update(id, progress: 0.5, detail: "Downloading")
        XCTAssertEqual(center.entries.first?.progress, 0.5)
        center.cancel(id); center.complete(id); center.cancel(id)
        XCTAssertEqual(cancellations, 1); XCTAssertEqual(center.entries.first?.state, .cancelled)
        center.retry(id); XCTAssertEqual(retries, 1)
        center.clearFinished(); XCTAssertTrue(center.entries.isEmpty)
        center.retry(id); XCTAssertEqual(retries, 1)
    }
    @MainActor func testLockCancelsAllWorkAndRejectsLateUpdates() {
        let center = DownloadCenter(); var cancellations = 0
        let id = center.begin(account: "Fixture", source: "Mail", destination: URL(fileURLWithPath: "/tmp/fixture.pdf"), cancel: { cancellations += 1 })
        center.clearFinished(); XCTAssertEqual(center.runningCount, 1)
        center.clearForLock(); center.update(id, progress: 1, detail: "Late"); center.complete(id)
        XCTAssertEqual(cancellations, 1); XCTAssertTrue(center.entries.isEmpty)
        center.clearForLock(); XCTAssertEqual(cancellations, 1)
    }
    @MainActor func testClosingAccountViewCancelsItsDownloadsAndRemovesItsRetries() {
        let center = DownloadCenter(); let owner = UUID(); var actions = 0
        let id = center.begin(account: "Fixture", source: "Mail", destination: URL(fileURLWithPath: "/tmp/fixture.pdf"), owner: owner, cancel: { actions += 1 }, retry: { actions += 10 })
        center.retire(owner: owner)
        center.retry(id)
        XCTAssertEqual(actions, 1); XCTAssertEqual(center.entries.first?.state, .cancelled)
        XCTAssertFalse(center.entries.first?.canRetry ?? true)
    }

    @MainActor func testCompletedDownloadCannotBeCancelledOrRetried() {
        let center = DownloadCenter(); var actions = 0
        let id = center.begin(account: "Fixture", source: "Mail", destination: URL(fileURLWithPath: "/tmp/fixture.pdf"), cancel: { actions += 1 }, retry: { actions += 1 })
        center.update(id, progress: .nan, detail: "Unknown size")
        XCTAssertNil(center.entries.first?.progress)
        center.complete(id); center.cancel(id); center.retry(id)
        XCTAssertEqual(actions, 0); XCTAssertEqual(center.entries.first?.state, .completed)
        XCTAssertFalse(center.entries.first?.canRetry ?? true)
    }
}
