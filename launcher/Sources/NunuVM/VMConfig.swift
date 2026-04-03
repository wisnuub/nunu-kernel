import Foundation

struct VMConfig {
    let kernelPath: String
    let initrdPath: String
    let diskPaths: [String]
    let memoryMB: UInt64
    let cpuCount: Int
    let adbPort: Int

    var memoryBytes: UInt64 { memoryMB * 1024 * 1024 }
}
