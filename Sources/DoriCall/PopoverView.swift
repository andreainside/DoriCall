import SwiftUI
import ServiceManagement

/// 菜单栏点开的主面板:同事名单([🔔叫][👍],点名字展开输入框)+ 📢 广播 + 设置
struct PopoverView: View {
    @ObservedObject var network: PeerNetwork
    @ObservedObject var settings: AppSettings
    let me: Person
    let sendAction: (Person, MsgKind, String?) -> Void
    let broadcastAction: () -> Void

    @State private var expandedId: String?
    @State private var draft = ""
    @State private var launchAtLogin = false
    @State private var showColorPicker = false
    @FocusState private var focusedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🍎 DoriCall").font(.headline)
                Spacer()
                Text("我是 \(me.name)").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ForEach(Roster.people.filter { $0.id != me.id }) { p in
                row(p)
            }
            Divider()
            Button(action: broadcastAction) {
                HStack {
                    Spacer()
                    Text("📢 叫所有人").font(.body.weight(.medium))
                    Spacer()
                }
                .padding(.vertical, 5)
            }
            if showColorPicker {
                Divider()
                HStack(spacing: 6) {
                    ForEach(Self.palette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 15, height: 15)
                            .overlay(Circle().stroke(Color.primary.opacity(currentColorHex == hex ? 0.9 : 0),
                                                     lineWidth: 2))
                            .onTapGesture {
                                settings.myColorHex = hex
                                network.setMyColor(hex)   // 新色随后续消息和探测包散播给同事
                            }
                    }
                    Spacer()
                    Button("确认") { showColorPicker = false }.font(.caption)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Toggle("🔕 勿扰", isOn: $settings.dnd)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                Toggle("开机自启", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: launchAtLogin) { on in
                        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
                        if on { try? SMAppService.mainApp.register() }
                        else { try? SMAppService.mainApp.unregister() }
                    }
                Spacer()
                Circle()
                    .fill(Color(hex: currentColorHex))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                    .onTapGesture { showColorPicker.toggle() }
                    .help("挑选我的代表色")
                Button("退出") { NSApp.terminate(nil) }.font(.caption)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
    }

    /// 可选的代表色(深色为主,保证卡片上白字可读)
    private static let palette = ["E8537A", "F08C00", "E03131", "37B24D", "0CA678",
                                  "1C7ED6", "3B5BDB", "7048E8", "495057"]

    private var currentColorHex: String { settings.myColorHex ?? me.colorHex }

    /// 对方自选过代表色就用对方的,否则名单默认色
    private func displayColor(_ p: Person) -> Color {
        network.peerColors[p.id].map { Color(hex: $0) } ?? p.color
    }

    @ViewBuilder
    private func row(_ p: Person) -> some View {
        let online = network.onlineIds.contains(p.id)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(online ? displayColor(p) : Color.gray.opacity(0.3))
                    .frame(width: 9, height: 9)
                Button {
                    if expandedId == p.id {
                        expandedId = nil
                    } else {
                        expandedId = p.id
                        draft = ""
                        DispatchQueue.main.async { focusedId = p.id }
                    }
                } label: {
                    Text(p.name).font(.body)
                }
                .buttonStyle(.plain)
                .help("点名字输入短消息")
                if !online {
                    Text("离线").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("🔔") { sendAction(p, .call, nil) }.help("叫一下 \(p.name)")
                Button("👍") { sendAction(p, .thumbs, nil) }.help("给 \(p.name) 点赞")
            }
            if expandedId == p.id {
                HStack(spacing: 6) {
                    TextField("输入短消息,回车发送", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedId, equals: p.id)
                        .onSubmit { submit(p) }
                    Button("发送") { submit(p) }
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func submit(_ p: Person) {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        sendAction(p, .text, String(t.prefix(60)))
        draft = ""
        expandedId = nil
    }
}
