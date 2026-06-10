import Foundation
import Network

/// 局域网对等通信,三条腿走路:
/// 1. Bonjour 广播 + 发现 —— 多播畅通的网络(家里、热点)零配置就能用
/// 2. 固定端口 53535 + 网段轮询 —— 公司 Wi-Fi 常把多播过滤掉(实测办公室就是),
///    但点对点 TCP 是通的:每 15 秒把本机所在 /24 网段安静扫一圈,谁回 hello 回执谁在线
/// 3. TCP 短连接收发单行 JSON,收到回 delivered 回执;发送优先走已知直连 IP,失败退回 Bonjour
/// 无服务器;includePeerToPeer 同时启用 AWDL 兜底。
final class PeerNetwork: ObservableObject {
    static let serviceType = "_doricall._tcp"
    static let fixedPort: NWEndpoint.Port = 53535

    let me: Person
    @Published private(set) var onlineIds: Set<String> = []
    var onMessage: ((Msg) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var bonjourIds: Set<String> = []
    private var directPeers: [String: String] = [:]   // id → 直连 IP(固定端口探测可达)
    private var sweepTimer: Timer?
    private var sweeping = false

    init(me: Person) { self.me = me }

    func start() {
        startListener()
        startBrowser()
        startSweep()
    }

    // MARK: - 广播自己 & 接收消息

    private func startListener() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true
        // 固定端口绑不上(比如本机已有一个实例在跑)就退回随机端口:
        // Bonjour 仍可发现它,只是不参与网段轮询 —— 双实例自测场景
        let l = (try? NWListener(using: params, on: Self.fixedPort)) ?? (try? NWListener(using: params))
        guard let l else {
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
                // 回送达回执,然后关连接(hello 探测也走这里:回执即"我在线")
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

    // MARK: - 发现同事(腿一:Bonjour)

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
            self.bonjourIds = ids
            self.refreshOnline()
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

    // MARK: - 发现同事(腿二:固定端口网段轮询)

    private func startSweep() {
        sweepOnce()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.sweepOnce()
        }
    }

    /// 扫一圈本机所在 /24:对每个 IP 的固定端口发 hello,收到回执就记下「这个人在这个 IP」
    private func sweepOnce() {
        guard !sweeping, let (ip, mask) = Self.localIPv4() else { return }
        sweeping = true
        var network = ip & mask
        var count = ~mask &+ 1
        if count == 0 || count > 256 {   // 大网段只扫自己所在的 /24,不当扫描器
            network = ip & 0xFFFF_FF00
            count = 256
        }
        var targets: [String] = []
        if count > 2 {
            for off in 1...(count - 2) {
                let host = network &+ off
                if host != ip { targets.append(Self.ipString(host)) }
            }
        }
        var found: [String: String] = [:]
        let batch = 64
        func runBatch(_ start: Int) {
            if start >= targets.count {
                self.directPeers = found
                self.refreshOnline()
                self.sweeping = false
                return
            }
            let group = DispatchGroup()
            for t in targets[start..<min(start + batch, targets.count)] {
                group.enter()
                self.probe(t) { id in
                    if let id { found[id] = t }
                    group.leave()
                }
            }
            group.notify(queue: .main) { runBatch(start + batch) }
        }
        runBatch(0)
    }

    /// 对单个 IP 的固定端口发 hello,2.5 秒内拿到 delivered 回执则返回对方 id
    private func probe(_ ip: String, completion: @escaping (String?) -> Void) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 1
        let params = NWParameters(tls: nil, tcp: tcp)
        params.preferNoProxies = true
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: Self.fixedPort, using: params)
        var done = false
        func finish(_ id: String?) {
            guard !done else { return }
            done = true
            conn.cancel()
            completion(id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { finish(nil) }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let self,
                      var data = try? JSONEncoder().encode(
                        Msg(kind: .hello, id: UUID().uuidString, from: self.me.id, fromName: self.me.name)
                      ) else { finish(nil); return }
                data.append(0x0A)
                conn.send(content: data, completion: .contentProcessed { err in
                    if err != nil { finish(nil); return }
                    self.receiveLine(on: conn) { ackData in
                        guard let ackData,
                              let ack = try? JSONDecoder().decode(Msg.self, from: ackData),
                              ack.kind == .delivered else { finish(nil); return }
                        finish(ack.from)
                    }
                })
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        conn.start(queue: .main)
    }

    private func refreshOnline() {
        var ids = bonjourIds.union(directPeers.keys)
        ids.remove(me.id)
        if ids != onlineIds { onlineIds = ids }
    }

    // MARK: - 发送(优先直连 IP,失败退回 Bonjour 服务名)

    func send(_ msg: Msg, toId: String, completion: @escaping (Bool) -> Void) {
        var endpoints: [NWEndpoint] = []
        if let ip = directPeers[toId] {
            endpoints.append(.hostPort(host: NWEndpoint.Host(ip), port: Self.fixedPort))
        }
        endpoints.append(.service(name: toId, type: Self.serviceType, domain: "local.", interface: nil))
        trySend(msg, endpoints: endpoints, completion: completion)
    }

    private func trySend(_ msg: Msg, endpoints: [NWEndpoint], completion: @escaping (Bool) -> Void) {
        guard let ep = endpoints.first else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        sendOnce(msg, to: ep, timeout: 4) { [weak self] ok in
            if ok { completion(true) }
            else { self?.trySend(msg, endpoints: Array(endpoints.dropFirst()), completion: completion) }
        }
    }

    /// 短连接:连上 → 发一行 JSON → 等送达回执 → 关闭
    private func sendOnce(_ msg: Msg, to endpoint: NWEndpoint, timeout: TimeInterval,
                          completion: @escaping (Bool) -> Void) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        // 局域网直连,绝不走系统代理 —— 否则开着 Clash 等代理时连接会被代理吞掉
        params.preferNoProxies = true
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

    // MARK: - 本机网段工具

    /// en0/en1… 上的 IPv4 地址和子网掩码(host 字节序)
    private static func localIPv4() -> (ip: UInt32, mask: UInt32)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var best: (UInt32, UInt32)?
        var p = ifaddr
        while let cur = p {
            let ifa = cur.pointee
            p = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
                  let nm = ifa.ifa_netmask else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var addr = sockaddr_in()
            var mask = sockaddr_in()
            memcpy(&addr, sa, MemoryLayout<sockaddr_in>.size)
            memcpy(&mask, nm, MemoryLayout<sockaddr_in>.size)
            let ipValue = UInt32(bigEndian: addr.sin_addr.s_addr)
            let maskValue = UInt32(bigEndian: mask.sin_addr.s_addr)
            if best == nil || name == "en0" { best = (ipValue, maskValue) }
            if name == "en0" { break }
        }
        return best
    }

    private static func ipString(_ v: UInt32) -> String {
        "\((v >> 24) & 255).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)"
    }
}
