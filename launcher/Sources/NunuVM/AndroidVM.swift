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

    func start() async throws {
        let vzConfig = try buildConfiguration()
        try vzConfig.validate()

        let machine = VZVirtualMachine(configuration: vzConfig)
        machine.delegate = self
        self.vm = machine

        try await machine.start()
        print("nunu-vm: started")

        // Show window on main thread
        let display = config.display
        let window = VMWindow(displayConfig: display)
        self.vmWindow = window
        await MainActor.run { window.show(vm: machine) }
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
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("nunu-vm: stopped")
        stopContinuation?.resume()
        stopContinuation = nil
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        fputs("nunu-vm: stopped with error: \(error.localizedDescription)\n", stderr)
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
