import Foundation

/// An opaque sRGB color written as an HTML code, such as #1A73E8.
public struct HexColor: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    /// Accepts #RGB and #RRGGBB, with or without the leading #.
    public init?(_ text: String) {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit), digits.allSatisfy(\.isASCII) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let value = Int(digits, radix: 16) else { return nil }
        red = (value >> 16) & 0xFF
        green = (value >> 8) & 0xFF
        blue = value & 0xFF
    }

    public init(red: Double, green: Double, blue: Double) {
        func channel(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        self.red = channel(red)
        self.green = channel(green)
        self.blue = channel(blue)
    }

    public var code: String { String(format: "#%02X%02X%02X", red, green, blue) }

    /// Whether black text reads better than white on this color (WCAG relative luminance).
    public var prefersDarkText: Bool {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }
}
