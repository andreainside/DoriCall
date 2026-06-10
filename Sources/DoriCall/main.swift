import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var network: PeerNetwork?
    private let cardStore = CardStore()
    private let settings = AppSettings()
    private var panel: FloatingPanel?
    private var firstRun: FirstRunController?
    private var blinkTimer: Timer?
    private var blinkOn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 测试/调试用:--dock 让应用显示在程序坞(便于自动化工具识别);正常运行只在菜单栏
        NSApp.setActivationPolicy(CommandLine.arguments.contains("--dock") ? .regular : .accessory)
        // 测试用:--whoami <id> 跳过身份选择(不写 UserDefaults)
        if let i = CommandLine.arguments.firstIndex(of: "--whoami"), i + 1 < CommandLine.arguments.count {
            Identity.overrideId = CommandLine.arguments[i + 1]
        }
        if let me = Identity.current {
            start(me: me)
        } else {
            let fr = FirstRunController()
            firstRun = fr
            fr.show { [weak self] p in self?.start(me: p) }
        }
    }

    private func start(me: Person) {
        let net = PeerNetwork(me: me)
        network = net
        panel = FloatingPanel(store: cardStore) { [weak self] card, action in
            self?.respond(to: card, action: action)
        }
        cardStore.onChange = { [weak self] in
            self?.panel?.refresh()
            self?.updateBlink()
        }
        net.onMessage = { [weak self] msg in self?.handle(msg) }
        net.setMyColor(settings.myColorHex)
        net.start()
        setupStatusItem(me: me)
        // 仅 /Applications 里的正式安装版注册开机自启;编译产物 build/DoriCall.app 不注册,
        // 否则登录项会指向随时被删的编译目录。重复 register 无害,顺带把旧注册纠正过来。
        if Bundle.main.bundlePath.hasPrefix("/Applications/") {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: - 收消息

    private func handle(_ msg: Msg) {
        let from = (Roster.person(id: msg.from)
            ?? Person(id: msg.from, name: msg.fromName, colorHex: "868E96", sound: "Glass"))
            .withColor(msg.color)   // 对方自选了代表色就用对方的
        switch msg.kind {
        case .call:
            let isBroadcast = msg.broadcast == true
            let card = CardStore.Card(style: .call, from: from,
                                      title: isBroadcast ? "📢 \(from.name) 叫大家" : "\(from.name) 在叫你",
                                      detail: nil, sourceMsgId: msg.id, broadcast: isBroadcast, face: "dori-loud")
            cardStore.push(card)
            if settings.dnd { autoReplyDND(msg, from: from) } else {
                Sounds.incoming(from: from)
                scheduleAutoDismiss(card)
            }
        case .text:
            let card = CardStore.Card(style: .text, from: from, title: "💬 \(from.name)",
                                      detail: msg.text ?? "", sourceMsgId: msg.id, broadcast: false, face: "dori-wink")
            cardStore.push(card)
            if settings.dnd { autoReplyDND(msg, from: from) } else {
                Sounds.incoming(from: from)
                scheduleAutoDismiss(card)
            }
        case .thumbs:
            cardStore.push(.init(style: .thumbs, from: from, title: "\(from.name) 给你点了个赞",
                                 detail: nil, sourceMsgId: msg.id, broadcast: false, face: "dori-thumbsup"), autoDismiss: 6)
            if !settings.dnd { Sounds.thumbs() }
        case .response:
            let label: String
            let face: String?
            switch msg.action {
            case "ok":   label = "👌 \(from.name):收到"; face = "dori-victory"
            case "wait": label = "🫷 \(from.name):等会"; face = "dori-working"
            case "dnd":  label = "🔕 \(from.name) 勿扰中,看到会回你"; face = "dori-sleep"
            default:     label = "\(from.name) 已回应"; face = nil
            }
            cardStore.push(.init(style: .info, from: from, title: label,
                                 detail: nil, sourceMsgId: msg.id, broadcast: false, face: face), autoDismiss: 4)
            if !settings.dnd { Sounds.info() }
        case .delivered, .hello:
            break
        }
    }

    /// 勿扰中自动回复:卡片照常静默堆在右上角,对方立刻知道你勿扰
    private func autoReplyDND(_ msg: Msg, from: Person) {
        guard let net = network else { return }
        let resp = Msg(kind: .response, id: UUID().uuidString, from: net.me.id, fromName: net.me.name,
                       action: "dnd", replyTo: msg.id, color: settings.myColorHex)
        net.send(resp, toId: from.id) { _ in }
    }

    /// 10 秒没点按钮 → 静默收起卡片,不给对方发任何回执(已被点掉则什么也不发生)
    private func scheduleAutoDismiss(_ card: CardStore.Card) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.cardStore.remove(card.id)
        }
    }

    /// 点了「收到 👌」/「等会 🫷」
    private func respond(to card: CardStore.Card, action: String) {
        defer { cardStore.remove(card.id) }
        guard let net = network, let from = card.from, card.needsResponse else { return }
        let resp = Msg(kind: .response, id: UUID().uuidString, from: net.me.id, fromName: net.me.name,
                       action: action, replyTo: card.sourceMsgId, color: settings.myColorHex)
        net.send(resp, toId: from.id) { _ in }
    }

    // MARK: - 发消息

    private func send(kind: MsgKind, to p: Person, text: String?) {
        guard let net = network else { return }
        popover.performClose(nil)
        let msg = Msg(kind: kind, id: UUID().uuidString, from: net.me.id, fromName: net.me.name, text: text,
                      color: settings.myColorHex)
        net.send(msg, toId: p.id) { [weak self] ok in
            guard let self else { return }
            let title = ok ? "✓ 已送达 \(p.name)" : "✗ \(p.name) 不在线,没送到"
            self.cardStore.push(.init(style: .info, from: nil, title: title, detail: nil,
                                      sourceMsgId: nil, broadcast: false), autoDismiss: 3)
        }
    }

    private func broadcast() {
        guard let net = network else { return }
        popover.performClose(nil)
        let targets = Roster.people.filter { $0.id != net.me.id && net.onlineIds.contains($0.id) }
        guard !targets.isEmpty else {
            cardStore.push(.init(style: .info, from: nil, title: "✗ 没有在线的同事", detail: nil,
                                 sourceMsgId: nil, broadcast: false), autoDismiss: 3)
            return
        }
        var delivered = 0
        let group = DispatchGroup()
        for t in targets {
            group.enter()
            let msg = Msg(kind: .call, id: UUID().uuidString, from: net.me.id, fromName: net.me.name,
                          broadcast: true, color: settings.myColorHex)
            net.send(msg, toId: t.id) { ok in
                if ok { delivered += 1 }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.cardStore.push(.init(style: .info, from: nil,
                                       title: "📢 已叫到 \(delivered)/\(targets.count) 人",
                                       detail: nil, sourceMsgId: nil, broadcast: false), autoDismiss: 4)
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem(me: Person) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon(alert: false)
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            network: network!, settings: settings, me: me,
            sendAction: { [weak self] p, kind, text in self?.send(kind: kind, to: p, text: text) },
            broadcastAction: { [weak self] in self?.broadcast() }
        ))
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - 有未处理的叫人时,菜单栏图标闪烁

    /// 菜单栏常态图标:打包进 Resources 的 Dori 头像;裸跑(无 .app)时退回  符号
    private static let doriMenuIcon: NSImage? = {
        guard let path = Bundle.main.path(forResource: "menubar", ofType: "png"),
              let img = NSImage(contentsOfFile: path) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false   // 保留品牌彩色
        return img
    }()

    private static func icon(alert: Bool) -> NSImage? {
        if !alert, let dori = doriMenuIcon { return dori }
        let img = NSImage(systemSymbolName: alert ? "bell.fill" : "apple.logo",
                          accessibilityDescription: "DoriCall")
        img?.isTemplate = true
        return img
    }

    private func updateBlink() {
        let shouldBlink = cardStore.hasUrgent && !settings.dnd
        if shouldBlink, blinkTimer == nil {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.blinkOn.toggle()
                self.statusItem?.button?.image = Self.icon(alert: self.blinkOn)
            }
        } else if !shouldBlink, let t = blinkTimer {
            t.invalidate()
            blinkTimer = nil
            blinkOn = false
            statusItem?.button?.image = Self.icon(alert: false)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
