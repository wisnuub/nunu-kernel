import Foundation
import Virtualization

@main
struct NunuVM {
    static func main() async {
        let args = Arguments.parse()

        switch args.command {
        case .boot:
            await boot(args: args)
        case .version:
            print("nunu-vm 0.1.0")
        }
    }

    static func boot(args: Arguments) async {
        let config = VMConfig(
            kernelPath: args.kernel,
            initrdPath: args.initrd,
            diskPaths: args.disks,
            memoryMB: args.memoryMB,
            cpuCount: args.cpuCount,
            adbPort: args.adbPort
        )

        let vm = AndroidVM(config: config)

        do {
            try await vm.start()
            await vm.waitUntilStopped()
        } catch {
            fputs("nunu-vm: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
