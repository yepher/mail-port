import Foundation

public enum GoogleService: String, CaseIterable, Codable, Identifiable, Sendable {
    case gmail, calendar, drive, docs, sheets, slides, contacts, chat, meet, youtube, gemini, colab, notebooklm
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gmail: "Gmail"
        case .calendar: "Calendar"
        case .drive: "Drive"
        case .docs: "Docs"
        case .sheets: "Sheets"
        case .slides: "Slides"
        case .contacts: "Contacts"
        case .chat: "Chat"
        case .meet: "Meet"
        case .youtube: "YouTube"
        case .gemini: "Gemini"
        case .colab: "Colab"
        case .notebooklm: "NotebookLM"
        }
    }

    /// Live work here would stop if the page unloaded: an open call or a running notebook.
    public var canHibernate: Bool { self != .meet && self != .colab }

    /// Account rows already say whose mail it is, so Gmail reads as Mail there.
    public var shortTitle: String { self == .gmail ? "Mail" : title }

    public var subtitle: String {
        switch self {
        case .gmail: "Your inbox, exactly as you know it."
        case .calendar: "A little space for your schedule."
        case .drive: "Everything you're working on."
        case .docs: "Write together, in your account."
        case .sheets: "Your numbers, in your account."
        case .slides: "Your presentations, in your account."
        case .contacts: "The people in your world."
        case .chat: "Keep the conversation going."
        case .meet: "Meet face to face, from anywhere."
        case .youtube: "Each account keeps its own channel."
        case .gemini: "Think, write, and explore with Gemini."
        case .colab: "Work with Python notebooks in Colab."
        case .notebooklm: "Research with your sources and notes."
        }
    }

    public var symbol: String {
        switch self {
        case .gmail: "envelope.fill"
        case .calendar: "calendar"
        case .drive: "externaldrive.fill"
        case .docs: "doc.text.fill"
        case .sheets: "tablecells.fill"
        case .slides: "rectangle.on.rectangle.fill"
        case .contacts: "person.crop.rectangle.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .meet: "video.fill"
        case .youtube: "play.rectangle.fill"
        case .gemini: "sparkles"
        case .colab: "chevron.left.forwardslash.chevron.right"
        case .notebooklm: "book.closed.fill"
        }
    }

    public var url: URL {
        let address: String
        switch self {
        case .gmail: address = "https://mail.google.com/mail/u/0/#inbox"
        case .calendar: address = "https://calendar.google.com/calendar/u/0/r"
        case .drive: address = "https://drive.google.com/drive/u/0/my-drive"
        case .docs: address = "https://docs.google.com/document/u/0/"
        case .sheets: address = "https://docs.google.com/spreadsheets/u/0/"
        case .slides: address = "https://docs.google.com/presentation/u/0/"
        case .contacts: address = "https://contacts.google.com/u/0/"
        case .chat: address = "https://chat.google.com/"
        case .meet: address = "https://meet.google.com/"
        case .youtube: address = "https://www.youtube.com/"
        case .gemini: address = "https://gemini.google.com/app"
        case .colab: address = "https://colab.research.google.com/"
        case .notebooklm: address = "https://notebook.google.com/"
        }
        return URL(string: address)!
    }
}
