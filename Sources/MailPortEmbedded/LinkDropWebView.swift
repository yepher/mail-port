import AppKit
import WebKit
import MailPortCore

/// Handle link drops before WebKit treats them as page content. Other services
/// retain WebKit's normal drag handling (including Gmail file attachments).
@MainActor
final class LinkDropWebView: WKWebView {
    var acceptsYouTubeLinks = false
    var onYouTubeLinkDrop: ((URL) -> Bool)?

    func droppedYouTubeURL(from pasteboard: NSPasteboard) -> URL? {
        guard acceptsYouTubeLinks else { return nil }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        for url in urls {
            if let result = YouTubeLinkDrop.url(from: url.absoluteString) { return result }
        }
        return pasteboard.string(forType: .string).flatMap(YouTubeLinkDrop.url)
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if droppedYouTubeURL(from: sender.draggingPasteboard) != nil { return .copy }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if droppedYouTubeURL(from: sender.draggingPasteboard) != nil { return .copy }
        return super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if droppedYouTubeURL(from: sender.draggingPasteboard) != nil { return true }
        return super.prepareForDragOperation(sender)
    }
    func openDroppedYouTubeLink(from pasteboard: NSPasteboard) -> Bool {
        guard let url = droppedYouTubeURL(from: pasteboard) else { return false }
        return onYouTubeLinkDrop?(url) ?? false
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if droppedYouTubeURL(from: sender.draggingPasteboard) != nil { return openDroppedYouTubeLink(from: sender.draggingPasteboard) }
        return super.performDragOperation(sender)
    }
}
