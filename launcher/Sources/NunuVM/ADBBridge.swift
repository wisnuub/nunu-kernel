import Foundation
import Network

// ADBBridge waits for the Android ADB daemon to come up inside the VM,
// then forwards host 127.0.0.1:<hostPort> → guest <guestIP>:5555.
//
// This lets nunu run `adb connect 127.0.0.1:5555` regardless of what
// NAT IP the guest received — the launcher handles the routing.
//
// macOS Virtualization.framework NAT:
//   Host (gateway): 192.168.64.1
//   First guest:    192.168.64.2  (default guestIP)

actor ADBBridge {
    private let hostPort: Int
    private let guestIP: String
    private let guestPort: Int = 5555

    private var listener: NWListener?
    private var isRunning = false

    init(hostPort: Int = 5555, guestIP: String = "192.168.64.2") {
        self.hostPort = hostPort
        self.guestIP = guestIP
    }

    // Waits until ADB is reachable inside the VM, then starts forwarding.
    // Prints a JSON status line to stdout that nunu parses.
    func start() async {
        print("nunu-vm: waiting for ADB...")

        await waitForADB()

        do {
            try startForwarding()
            isRunning = true
            // nunu reads this line from the process stdout to know ADB is ready
            let status = #"{"event":"adb-ready","address":"127.0.0.1:\#(hostPort)"}"#
            print(status)
        } catch {
            fputs("nunu-vm: ADB forwarding failed: \(error)\n", stderr)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Poll until ADB port is open

    private func waitForADB(timeoutSeconds: Int = 120) async {
        let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
        while Date() < deadline {
            if await isADBReachable() { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        }
        fputs("nunu-vm: warning: ADB not reachable after \(timeoutSeconds)s\n", stderr)
    }

    private func isADBReachable() async -> Bool {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(guestIP)
            let port = NWEndpoint.Port(rawValue: UInt16(guestPort))!
            let conn = NWConnection(host: host, port: port, using: .tcp)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            conn.start(queue: .global())

            // Timeout probe after 1s
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if conn.state != .ready {
                    conn.cancel()
                }
            }
        }
    }

    // MARK: - TCP forwarding listener

    private func startForwarding() throws {
        let port = NWEndpoint.Port(rawValue: UInt16(hostPort))!
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: port
        )

        let l = try NWListener(using: params)
        self.listener = l

        l.newConnectionHandler = { [weak self] inbound in
            guard let self else { return }
            inbound.start(queue: .global())
            Task { await self.bridge(inbound: inbound) }
        }

        l.start(queue: .global())
    }

    // Bridge a single inbound connection to the guest ADB daemon
    private func bridge(inbound: NWConnection) async {
        let guestHost = NWEndpoint.Host(guestIP)
        let guestPort = NWEndpoint.Port(rawValue: UInt16(self.guestPort))!
        let outbound = NWConnection(host: guestHost, port: guestPort, using: .tcp)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            outbound.stateUpdateHandler = { state in
                if state == .ready { cont.resume() }
                else if case .failed = state { cont.resume() }
                else if case .cancelled = state { cont.resume() }
            }
            outbound.start(queue: .global())
        }

        // Pipe both directions concurrently
        async let _ = pipe(from: inbound, to: outbound)
        async let _ = pipe(from: outbound, to: inbound)
    }

    private func pipe(from source: NWConnection, to dest: NWConnection) async {
        while true {
            let data = await receive(from: source)
            guard let data, !data.isEmpty else { break }
            await send(data: data, to: dest)
        }
    }

    private func receive(from conn: NWConnection) async -> Data? {
        await withCheckedContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    fputs("nunu-vm: bridge recv error: \(error)\n", stderr)
                    cont.resume(returning: nil)
                } else if isComplete {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(returning: data)
                }
            }
        }
    }

    private func send(data: Data, to conn: NWConnection) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            conn.send(content: data, completion: .contentProcessed { _ in
                cont.resume()
            })
        }
    }
}
