import AppKit
import SwiftUI

/// 首次启动:选"我是谁",存下后不再询问
final class FirstRunController {
    private var window: NSWindow?

    func show(onPick: @escaping (Person) -> Void) {
        let view = FirstRunView { [weak self] p in
            Identity.save(p.id)
            self?.window?.close()
            self?.window = nil
            onPick(p)
        }
        let w = NSWindow(contentRect: .zero,
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "DoriCall"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: view)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct FirstRunView: View {
    let pick: (Person) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("🍎").font(.system(size: 40))
            Text("你是谁?").font(.title2.bold())
            Text("只需要选一次,以后开机自动运行").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(Roster.people) { p in
                    Button { pick(p) } label: {
                        VStack(spacing: 6) {
                            Circle().fill(p.color).frame(width: 14, height: 14)
                            Text(p.name).font(.body.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}
