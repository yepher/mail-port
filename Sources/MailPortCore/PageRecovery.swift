import Foundation

/// When a page that failed to load is worth retrying without being asked.
public enum PageRecovery {
    /// WebKit reports these when a navigation became a download or a policy stopped
    /// it. Nothing went wrong, so the page shouldn't show an error.
    public static func isExpected(domain: String, code: Int) -> Bool {
        (domain == NSURLErrorDomain && code == NSURLErrorCancelled)
            || (domain == "WebKitErrorDomain" && code == 102)
    }

    /// Failures that a later attempt can fix, such as being offline.
    public static func isTransient(domain: String, code: Int) -> Bool {
        domain == NSURLErrorDomain && [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
            NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed
        ].contains(code)
    }

    /// 5 seconds, doubling to at most 5 minutes.
    public static func delay(attempt: Int) -> TimeInterval {
        min(300, 5 * pow(2, Double(max(0, min(attempt, 10)))))
    }
}
