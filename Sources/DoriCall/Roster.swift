import SwiftUI

struct Person: Identifiable, Hashable {
    let id: String        // Bonjour 服务名:ASCII、全队唯一
    let name: String      // 显示名
    let colorHex: String  // 专属颜色(被叫卡片底色)
    let sound: String     // 专属来电提示音(macOS 系统音名)
    var color: Color { Color(hex: colorHex) }
}

enum Roster {
    static let people: [Person] = [
        Person(id: "wenxin",   name: "温馨",   colorHex: "E8537A", sound: "Glass"),
        Person(id: "jianing",  name: "嘉宁",   colorHex: "F08C00", sound: "Hero"),
        Person(id: "zhangwei", name: "张玮",   colorHex: "1C7ED6", sound: "Ping"),
        Person(id: "andrea",   name: "Andrea", colorHex: "37B24D", sound: "Purr"),
        Person(id: "haozhe",   name: "昊哲",   colorHex: "7048E8", sound: "Submarine"),
        Person(id: "luyifan",  name: "陆轶凡", colorHex: "0CA678", sound: "Funk"),
    ]
    static func person(id: String) -> Person? { people.first { $0.id == id } }
}

/// 我是谁:存 UserDefaults,首次启动选择;--whoami 参数可覆盖(测试用)
enum Identity {
    private static let key = "whoami"
    static var overrideId: String?
    static var current: Person? {
        if let o = overrideId { return Roster.person(id: o) }
        guard let id = UserDefaults.standard.string(forKey: key) else { return nil }
        return Roster.person(id: id)
    }
    static func save(_ id: String) { UserDefaults.standard.set(id, forKey: key) }
}

/// 全局开关(勿扰)
final class AppSettings: ObservableObject {
    @Published var dnd: Bool = UserDefaults.standard.bool(forKey: "dnd") {
        didSet { UserDefaults.standard.set(dnd, forKey: "dnd") }
    }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255.0,
                  green: Double((v >> 8) & 0xFF) / 255.0,
                  blue:  Double(v & 0xFF) / 255.0)
    }
}
