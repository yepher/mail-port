import Foundation

public enum GoogleService: String, CaseIterable, Codable, Identifiable, Sendable {
    case gmail, calendar, drive, contacts, chat, meet, gemini, colab, notebooklm
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gmail: "Gmail"
        case .calendar: "Calendar"
        case .drive: "Drive"
        case .contacts: "Contacts"
        case .chat: "Chat"
        case .meet: "Meet"
        case .gemini: "Gemini"
        case .colab: "Colab"
        case .notebooklm: "NotebookLM"
        }
    }

    public var subtitle: String {
        switch self {
        case .gmail: "Your inbox, exactly as you know it."
        case .calendar: "A little space for your schedule."
        case .drive: "Everything you're working on."
        case .contacts: "The people in your world."
        case .chat: "Keep the conversation going."
        case .meet: "Meet face to face, from anywhere."
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
        case .contacts: "person.crop.rectangle.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .meet: "video.fill"
        case .gemini: "sparkles"
        case .colab: "chevron.left.forwardslash.chevron.right"
        case .notebooklm: "book.closed.fill"
        }
    }

    public var shortcutDigit: String {
        switch self {
        case .gmail: "1"
        case .calendar: "2"
        case .drive: "3"
        case .contacts: "4"
        case .chat: "5"
        case .meet: "6"
        case .gemini: "7"
        case .colab: "8"
        case .notebooklm: "9"
        }
    }

    public var url: URL {
        let address: String
        switch self {
        case .gmail: address = "https://mail.google.com/mail/u/0/#inbox"
        case .calendar: address = "https://calendar.google.com/calendar/u/0/r"
        case .drive: address = "https://drive.google.com/drive/u/0/my-drive"
        case .contacts: address = "https://contacts.google.com/u/0/"
        case .chat: address = "https://chat.google.com/"
        case .meet: address = "https://meet.google.com/"
        case .gemini: address = "https://gemini.google.com/app"
        case .colab: address = "https://colab.research.google.com/"
        case .notebooklm: address = "https://notebook.google.com/"
        }
        return URL(string: address)!
    }
}
