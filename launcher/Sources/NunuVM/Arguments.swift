import Foundation

enum Command {
    case boot
    case version
}

struct Arguments {
    var command: Command = .boot
    var kernel: String = ""
    var initrd: String = ""
    var disks: [String] = []
    var memoryMB: UInt64 = 4096
    var cpuCount: Int = 4
    var adbPort: Int = 5555

    static func parse() -> Arguments {
        var args = Arguments()
        let raw = Array(CommandLine.arguments.dropFirst())
        var i = 0

        while i < raw.count {
            switch raw[i] {
            case "--version":
                args.command = .version
            case "--kernel":
                i += 1; if i < raw.count { args.kernel = raw[i] }
            case "--initrd":
                i += 1; if i < raw.count { args.initrd = raw[i] }
            case "--disk":
                i += 1; if i < raw.count { args.disks.append(raw[i]) }
            case "--memory":
                i += 1; if i < raw.count { args.memoryMB = UInt64(raw[i]) ?? 4096 }
            case "--cores":
                i += 1; if i < raw.count { args.cpuCount = Int(raw[i]) ?? 4 }
            case "--adb-port":
                i += 1; if i < raw.count { args.adbPort = Int(raw[i]) ?? 5555 }
            default:
                break
            }
            i += 1
        }

        return args
    }
}
