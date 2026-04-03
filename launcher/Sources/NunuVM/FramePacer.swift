import AppKit
import QuartzCore
import Metal

// FramePacer drives rendering in sync with the display refresh rate using
// CVDisplayLink — the same mechanism used by AAA game engines on macOS.
//
// Why this matters:
//   VZVirtualMachineView renders when the VM pushes frames. If the VM pushes
//   at 63fps on a 60Hz display, every ~20 frames a double-frame lands in the
//   same vsync window, causing a visible stutter. CVDisplayLink inverts this:
//   the display pulls frames on its own schedule, discarding extras and
//   holding the last frame if the VM is momentarily slow — just like a
//   real game engine's present queue.

class FramePacer {
    private var displayLink: CVDisplayLink?
    private var onTick: (() -> Void)?

    init() {}

    func start(screen: NSScreen? = nil, onTick: @escaping () -> Void) {
        self.onTick = onTick

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else {
            fputs("nunu-vm: warning: could not create CVDisplayLink, frame pacing disabled\n", stderr)
            return
        }

        // Pass self as context so the C callback can reach the Swift instance
        let ctx = Unmanaged.passRetained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, ctx -> CVReturn in
            guard let ctx else { return kCVReturnError }
            let pacer = Unmanaged<FramePacer>.fromOpaque(ctx).takeUnretainedValue()
            pacer.onTick?()
            return kCVReturnSuccess
        }, ctx)

        // Pin to the screen the window is on
        if let screen = screen ?? NSScreen.main {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let id = displayID {
                CVDisplayLinkSetCurrentCGDisplay(link, id)
            }
        }

        CVDisplayLinkStart(link)
    }

    func stop() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    deinit { stop() }
}

// FrameStats tracks frame timing for diagnostics.
// nunu can read these to show an FPS counter / frame time graph.
struct FrameStats {
    private(set) var fps: Double = 0
    private(set) var frameTimeMs: Double = 0
    private(set) var droppedFrames: Int = 0

    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsAccumulator: CFTimeInterval = 0

    mutating func record(timestamp: CFTimeInterval) {
        if lastTimestamp > 0 {
            let delta = timestamp - lastTimestamp
            frameTimeMs = delta * 1000

            // A "dropped" frame is one that took more than 1.5x the expected
            // frame time (e.g. >25ms on a 60Hz display)
            let expectedMs = 1000.0 / 60.0
            if frameTimeMs > expectedMs * 1.5 {
                droppedFrames += 1
            }

            fpsAccumulator += delta
            frameCount += 1

            if fpsAccumulator >= 1.0 {
                fps = Double(frameCount) / fpsAccumulator
                frameCount = 0
                fpsAccumulator = 0
            }
        }
        lastTimestamp = timestamp
    }
}
