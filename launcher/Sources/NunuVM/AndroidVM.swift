import AppKit
import Foundation
import Virtualization

class AndroidVM: NSObject {
    private let config: VMConfig
    private var vm: VZVirtualMachine?
    private var vmWindow: VMWindow?
    private var stopContinuation: CheckedContinuation<Void, Never>?

    init(config: VMConfig) {
        self.config = config
    }

    private var framePacer: FramePacer?
    private var adbBridge: ADBBridge?
    private var adbInput: ADBInput?
    private var gestureObservers: [NSObjectProtocol] = []

    func start() async throws {
        // Apply all host-side performance optimisations before the VM starts
        Performance.apply()

        let vzConfig = try buildConfiguration()
        try vzConfig.validate()

        let machine = VZVirtualMachine(configuration: vzConfig)
        machine.delegate = self
        self.vm = machine

        try await machine.start()
        print(#"{"event":"started"}"#)

        // Start ADB bridge in background — polls until ADB daemon is up
        let bridge = ADBBridge(hostPort: config.adbPort, guestIP: "192.168.64.2")
        self.adbBridge = bridge
        let display = config.display
        let adbPort = config.adbPort
        Task {
            await bridge.start()
            // Once ADB is ready, wire up gesture input injection
            let input = ADBInput(
                adbAddress: "127.0.0.1:\(adbPort)",
                displayWidth: display.widthPx,
                displayHeight: display.heightPx
            )
            self.adbInput = input
            await MainActor.run { self.subscribeGestures(input: input) }
        }

        // Show window and start frame pacer on main thread
        await MainActor.run {
            let window = VMWindow(displayConfig: display)
            self.vmWindow = window
            window.show(vm: machine)

            // Start CVDisplayLink-driven frame pacing once window is visible
            let pacer = FramePacer()
            pacer.start(screen: NSScreen.main) {
                DispatchQueue.main.async {
                    window.requestFrame()
                }
            }
            self.framePacer = pacer
        }
    }

    func waitUntilStopped() async {
        await withCheckedContinuation { continuation in
            self.stopContinuation = continuation
        }
    }

    // MARK: - Configuration

    private func buildConfiguration() throws -> VZVirtualMachineConfiguration {
        let c = VZVirtualMachineConfiguration()

        c.memorySize = config.memoryBytes
        c.cpuCount = max(1, min(config.cpuCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount))

        c.bootLoader = try makeBootLoader()
        c.storageDevices = try makeStorageDevices()
        c.networkDevices = makeNetworkDevices()
        c.graphicsDevices = [makeGraphicsDevice(display: config.display)]
        c.keyboards = makeKeyboards()
        c.pointingDevices = makePointingDevices()
        c.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        c.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        return c
    }

    private func makeBootLoader() throws -> VZLinuxBootLoader {
        guard !config.kernelPath.isEmpty else {
            throw VMError.missingKernel
        }
        let kernelURL = URL(fileURLWithPath: config.kernelPath)
        let loader = VZLinuxBootLoader(kernelURL: kernelURL)

        if !config.initrdPath.isEmpty {
            loader.initialRamdiskURL = URL(fileURLWithPath: config.initrdPath)
        }

        // Android kernel cmdline — mirrors Cuttlefish defaults
        loader.commandLine = [
            "root=/dev/vda",
            "rootfstype=ext4",
            "rw",
            "androidboot.hardware=cuttlefish",
            "androidboot.serialno=nunu0",
            "androidboot.console=ttyS0",
            "console=ttyS0",
            "loglevel=7",
        ].joined(separator: " ")

        return loader
    }

    private func makeStorageDevices() throws -> [VZStorageDeviceConfiguration] {
        guard !config.diskPaths.isEmpty else {
            throw VMError.noDisk
        }

        return try config.diskPaths.map { path in
            let url = URL(fileURLWithPath: path)
            let attachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: false)
            return VZVirtioBlockDeviceConfiguration(attachment: attachment)
        }
    }

    private func makeNetworkDevices() -> [VZNetworkDeviceConfiguration] {
        let device = VZVirtioNetworkDeviceConfiguration()
        // NAT — gives Android internet access and allows ADB over TCP (port forwarding handled by nunu)
        device.attachment = VZNATNetworkDeviceAttachment()
        return [device]
    }
}

// MARK: - VZVirtualMachineDelegate

extension AndroidVM: VZVirtualMachineDelegate {
    // MARK: - Gesture → ADB wiring

    @MainActor
    private func subscribeGestures(input: ADBInput) {
        let center = NotificationCenter.default

        let w = config.display.widthPx
        let h = config.display.heightPx

        let pinchObs = center.addObserver(forName: .nunuVMPinch, object: nil, queue: .main) { note in
            guard let scale = note.userInfo?["scale"] as? Double else { return }
            Task { await input.pinch(scale: scale, centerX: w / 2, centerY: h / 2) }
        }

        let scrollObs = center.addObserver(forName: .nunuVMScroll, object: nil, queue: .main) { note in
            guard let dx = note.userInfo?["dx"] as? CGFloat,
                  let dy = note.userInfo?["dy"] as? CGFloat,
                  let x  = note.userInfo?["x"]  as? CGFloat,
                  let y  = note.userInfo?["y"]  as? CGFloat else { return }
            let conv = TouchCoordinateConverter(
                viewSize: CGSize(width: w, height: h),
                displayWidth: w, displayHeight: h
            )
            let (px, py) = conv.convert(NSPoint(x: x, y: y))
            Task { await input.scroll(fromX: px, fromY: py, dx: Double(dx), dy: Double(-dy)) }
        }

        gestureObservers = [pinchObs, scrollObs]
    }

    @MainActor
    private func unsubscribeGestures() {
        gestureObservers.forEach { NotificationCenter.default.removeObserver($0) }
        gestureObservers.removeAll()
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print(#"{"event":"stopped"}"#)
        framePacer?.stop()
        Task { await adbBridge?.stop() }
        Task { await MainActor.run { self.unsubscribeGestures() } }
        Performance.teardown()
        stopContinuation?.resume()
        stopContinuation = nil
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        let msg = error.localizedDescription
        print(#"{"event":"error","message":"\#(msg)"}"#)
        framePacer?.stop()
        Task { await adbBridge?.stop() }
        Task { await MainActor.run { self.unsubscribeGestures() } }
        Performance.teardown()
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

// MARK: - Errors

enum VMError: LocalizedError {
    case missingKernel
    case noDisk

    var errorDescription: String? {
        switch self {
        case .missingKernel: return "No kernel specified. Pass --kernel <path>"
        case .noDisk:        return "No disk image specified. Pass --disk <path>"
        }
    }
}
