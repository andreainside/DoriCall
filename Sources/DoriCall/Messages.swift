import Foundation

enum MsgKind: String, Codable {
    case call       // 🔔 叫一下
    case thumbs     // 👍 点赞
    case text       // 💬 短文字
    case response   // 被叫方的回应(ok / wait / dnd)
    case delivered  // 链路层送达回执
    case hello      // 在线探测(网段轮询用),静默回执、不弹卡
}

/// 网络上传输的唯一消息结构:单行 JSON + '\n' 结尾
struct Msg: Codable {
    var kind: MsgKind
    var id: String
    var from: String            // 发送者 canonical id(Bonjour 服务名)
    var fromName: String        // 发送者显示名(roster 不一致时容错显示)
    var text: String? = nil     // kind == .text 的正文
    var action: String? = nil   // kind == .response: "ok" | "wait" | "dnd"
    var replyTo: String? = nil  // kind == .response: 对应原消息 id
    var broadcast: Bool? = nil  // kind == .call 且为 📢 广播时 true
    var color: String? = nil    // 发送者自选代表色 hex;随消息/hello/回执传播,nil = 名单默认色
}
