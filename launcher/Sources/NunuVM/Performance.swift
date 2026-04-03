import Foundation
import IOKit.pwr_mgt

// Performance applies all host-side optimisations before the VM starts.
// Goal: consistent frame times, no CPU throttle, no memory pressure surprises.
struct Performance {

    // Activity assertion token — must stay alive for the duration of the session
    private static var activityToken: NSObjectProtocol?
    private static var pmAssertionID: IOPMAssertionID = 0

    static func apply() {
        disableAppNap()
        preventSleep()
        raiseProcessPriority()
        configureQoS()
    }

    static func teardown() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        if pmAssertionID != 0 {
            IOPMAssertionRelease(pmAssertionID)
            pmAssertionID = 0
        }
    }

    // MARK: - App Nap

    // App Nap throttles background apps to save power.
    // When nunu spawns nunu-vm, macOS may consider it "background" and throttle it.
    // This prevents that entirely.
    private static func disableAppNap() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiated,
                .latencyCritical,
                .idleSystemSleepDisabled,
                .suddenTerminationDisabled,
                .automaticTerminationDisabled,
            ],
            reason: "Android VM gaming session"
        )
    }

    // MARK: - Sleep prevention

    // Prevent the system from sleeping or the display from dimming mid-game.
    private static func preventSleep() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "nunu-vm gaming session" as CFString,
            &pmAssertionID
        )
        if result != kIOReturnSuccess {
            fputs("nunu-vm: warning: could not prevent system sleep\n", stderr)
        }
    }

    // MARK: - Process priority

    // setpriority(PRIO_PROCESS, 0, -10) — move the process up the scheduler queue.
    // -20 is maximum but requires root; -10 is achievable without entitlements and
    // meaningfully reduces the chance of the VM being preempted during a frame.
    private static func raiseProcessPriority() {
        let result = setpriority(PRIO_PROCESS, 0, -10)
        if result != 0 {
            fputs("nunu-vm: warning: could not raise process priority (errno \(errno))\n", stderr)
        }
    }

    // MARK: - QoS

    // Mark the main thread as user-interactive — the highest QoS class on Darwin.
    // macOS uses this to prefer scheduling this thread over background work.
    // Virtualization.framework creates its own VM threads but they inherit the
    // process QoS class, so this lifts all VM threads.
    private static func configureQoS() {
        Thread.current.qualityOfService = .userInteractive
        DispatchQueue.main.async {
            Thread.current.qualityOfService = .userInteractive
        }
    }
}
