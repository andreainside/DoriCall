import AppKit
import SwiftUI

enum Sounds {
    static func incoming(from p: Person?) { NSSound(named: p?.sound ?? "Glass")?.play() }
    static func thumbs() { NSSound(named: "Pop")?.play() }
    static func info() { NSSound(named: "Tink")?.play() }
}

// MARK: - 卡片数据

final class CardStore: ObservableObject {
    struct Card: Identifiable {
        enum Style { case call, thumbs, text, info }
        let id = UUID()
        let style: Style
        let from: Person?       // info 卡可为 nil
        let title: String
        let detail: String?     // text 卡正文
        let sourceMsgId: String?
        let broadcast: Bool
        var needsResponse: Bool { style == .call || style == .text }
    }

    @Published private(set) var cards: [Card] = []
    var onChange: (() -> Void)?

    func push(_ card: Card, autoDismiss: TimeInterval? = nil) {
        cards.append(card)
        onChange?()
        if let t = autoDismiss {
            let id = card.id
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.remove(id) }
        }
    }

    func remove(_ id: UUID) {
        cards.removeAll { $0.id == id }
        onChange?()
    }

    var hasUrgent: Bool { cards.contains { $0.needsResponse } }
}

// MARK: - 卡片视图

struct CardStackView: View {
    @ObservedObject var store: CardStore
    let onRespond: (CardStore.Card, String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(store.cards) { card in
                CardView(card: card,
                         onRespond: onRespond,
                         onDismiss: { store.remove(card.id) })
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

struct CardView: View {
    let card: CardStore.Card
    let onRespond: (CardStore.Card, String) -> Void
    let onDismiss: () -> Void
    @State private var shakeX: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            if card.style == .call || card.style == .text {
                AppleManView(ringing: true)
            } else if card.style == .thumbs {
                Text("👍").font(.system(size: 44))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(card.title)
                    .font(card.style == .info ? .callout.weight(.medium) : .title3.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = card.detail, !d.isEmpty {
                    Text(d)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if card.needsResponse {
                    HStack(spacing: 10) {
                        respButton("收到 👌", "ok")
                        respButton("等会 🫷", "wait")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(card.style == .info ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(bgColor))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
        .offset(x: shakeX)
        .onAppear {
            guard card.needsResponse else { return }
            // 抖几下(MSN 致敬),0.6s 后归位
            withAnimation(.linear(duration: 0.06).repeatCount(9, autoreverses: true)) { shakeX = 5 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.linear(duration: 0.05)) { shakeX = 0 }
            }
        }
        .onTapGesture {
            if !card.needsResponse { onDismiss() }   // 👍 和提示卡点一下消失
        }
    }

    private func respButton(_ label: String, _ action: String) -> some View {
        Button { onRespond(card, action) } label: {
            Text(label)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.22)))
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var bgColor: Color {
        switch card.style {
        case .info: return Color.black.opacity(0.78)
        default: return card.from?.color ?? Color.gray
        }
    }
}

// MARK: - 置顶悬浮面板(屏幕右上角,全屏 App 之上也可见)

final class FloatingPanel {
    private let panel: NSPanel
    private let store: CardStore

    init(store: CardStore, onRespond: @escaping (CardStore.Card, String) -> Void) {
        self.store = store
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 388, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: CardStackView(store: store, onRespond: onRespond))
    }

    /// 卡片增减后重算大小、贴右上角;无卡片时隐藏
    func refresh() {
        DispatchQueue.main.async { [self] in
            if store.cards.isEmpty {
                panel.orderOut(nil)
                return
            }
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            var size = panel.contentView?.fittingSize ?? NSSize(width: 388, height: 140)
            if size.width < 10 || size.height < 10 { size = NSSize(width: 388, height: 140) }
            let vf = screen.visibleFrame
            let rect = NSRect(x: vf.maxX - size.width - 6,
                              y: vf.maxY - size.height - 6,
                              width: size.width, height: size.height)
            panel.setFrame(rect, display: true)
            panel.orderFrontRegardless()
        }
    }
}
