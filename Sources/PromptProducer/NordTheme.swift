import SwiftUI

enum NordTheme {
    static let radius: CGFloat = 10
    static let controlRadius: CGFloat = radius
    static let windowRadius: CGFloat = 16
    static let commandBarWindowRadius: CGFloat = 26

    static let polarNight0 = Color(red: 46 / 255, green: 52 / 255, blue: 64 / 255)
    static let polarNight1 = Color(red: 59 / 255, green: 66 / 255, blue: 82 / 255)
    static let polarNight2 = Color(red: 67 / 255, green: 76 / 255, blue: 94 / 255)
    static let polarNight3 = Color(red: 76 / 255, green: 86 / 255, blue: 106 / 255)

    static let snow0 = Color(red: 216 / 255, green: 222 / 255, blue: 233 / 255)
    static let snow1 = Color(red: 229 / 255, green: 233 / 255, blue: 240 / 255)
    static let snow2 = Color(red: 236 / 255, green: 239 / 255, blue: 244 / 255)

    static let frost0 = Color(red: 143 / 255, green: 188 / 255, blue: 187 / 255)
    static let frost1 = Color(red: 136 / 255, green: 192 / 255, blue: 208 / 255)
    static let frost2 = Color(red: 129 / 255, green: 161 / 255, blue: 193 / 255)
    static let frost3 = Color(red: 94 / 255, green: 129 / 255, blue: 172 / 255)

    static let red = Color(red: 191 / 255, green: 97 / 255, blue: 106 / 255)
    static let orange = Color(red: 208 / 255, green: 135 / 255, blue: 112 / 255)
    static let yellow = Color(red: 235 / 255, green: 203 / 255, blue: 139 / 255)
    static let green = Color(red: 163 / 255, green: 190 / 255, blue: 140 / 255)
    static let purple = Color(red: 180 / 255, green: 142 / 255, blue: 173 / 255)

    static let background = polarNight0
    static let panel = polarNight1
    static let elevatedPanel = polarNight2
    static let field = polarNight0.opacity(0.78)
    static let text = snow2
    static let secondaryText = snow0.opacity(0.76)
    static let tertiaryText = snow0.opacity(0.54)
    static let separator = polarNight3.opacity(0.68)
    static let accent = frost1
    static let selectedFill = frost3.opacity(0.36)
    static let selectedStroke = frost1.opacity(0.72)
}
