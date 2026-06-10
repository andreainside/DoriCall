import Foundation
import Network

/// 局域网对等通信:Bonjour 广播自己 + 发现同事 + TCP 短连接收发单条 JSON。
/// 无服务器;includePeerToPeer 同时启用 AWDL,办公室 Wi-Fi 设备隔离时兜底。
final class PeerNetwork: ObservableObject {
    static let serviceType = "_doricall._tcp"

    let me: Person
    @Published private(set) var onlineIds: Set<String> = []
    var onMessage: ((Msg) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?

    init(me: Person) { self.me = me }

    func start() {
        startListener()
        startBrowser()
    }

    // MARK: - 广播自己 & 接收消息

    private func startListener() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        guard let l = try? NWListener(using: params) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startListener() }
            return
        }
        l.service = NWListener.Service(name: me.id, type: Self.serviceType)
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            self?.receiveLine(on: conn) { data in
                guard let self, let data,
                      let msg = try? JSONDecoder().decode(Msg.self, from: data) else {
                    conn.cancel()
                    return
                }
                // 回送达回执,然后关连接
                var ack = (try? JSONEncoder().encode(
                    Msg(kind: .delivered, id: UUID().uuidString, from: self.me.id, fromName: self.me.name)
                )) ?? Data()
                ack.append(0x0A)
                conn.send(content: ack, completion: .contentProcessed { _ in conn.cancel() })
                self.onMessage?(msg)
            }
        }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                l.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.startListener() }
            }
        }
        l.start(queue: .main)
        listener = l
    }

    // MARK: - 发现同事

    private func startBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var ids = Set<String>()
            for r in results {
                if case let .service(name, _, _, _) = r.endpoint { ids.insert(name) }
            }
            ids.remove(self.me.id)
            self.onlineIds = ids
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                b.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.startBrowser() }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    // MARK: - 发送(短连接:连上 → 发一行 JSON → 等送达回执 → 关闭)

    func send(_ msg: Msg, toId: String, timeout: TimeInterval = 6, completion: @escaping (Bool) -> Void) {
        let endpoint = NWEndpoint.service(name: toId, type: Self.serviceType, domain: "local.", interface: nil)
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let conn = NWConnection(to: endpoint, using: params)

        var finished = false
        func finish(_ ok: Bool) {
            guard !finished else { return }
            finished = true
            conn.cancel()
            DispatchQueue.main.async { completion(ok) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(false) }

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard var data = try? JSONEncoder().encode(msg) else { finish(false); return }
                data.append(0x0A)
                conn.send(content: data, completion: .contentProcessed { err in
                    if err != nil { finish(false); return }
                    self?.receiveLine(on: conn) { ackData in
                        guard let ackData,
                              let ack = try? JSONDecoder().decode(Msg.self, from: ackData),
                              ack.kind == .delivered else {
                            finish(false)
                            return
                        }
                        finish(true)
                    }
                })
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        conn.start(queue: .main)
    }

    // MARK: - 按行读取

    private func receiveLine(on conn: NWConnection, buffer: Data = Data(), completion: @escaping (Data?) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var buf = buffer
            if let data { buf.append(data) }
            if let idx = buf.firstIndex(of: 0x0A) {
                completion(Data(buf.prefix(upTo: idx)))
            } else if isComplete || error != nil {
                completion(buf.isEmpty ? nil : buf)
            } else {
                self?.receiveLine(on: conn, buffer: buf, completion: completion)
            }
        }
    }
}
