import AppKit
import Virtualization

// DisplayConfig holds resolution + DPI + optional color calibration
struct DisplayConfig {
    var widthPx: Int = 1080
    var heightPx: Int = 1920
    var ppi: Int = 420          // ~Pixel 7 density
    var refreshRate: Int = 60
    var colorCalibration: ColorCalibration = .default
}

struct ColorCalibration {
    var brightness: Float = 1.0   // 0.5 – 1.5
    var contrast: Float = 1.0     // 0.5 – 1.5
    var saturation: Float = 1.0   // 0.0 – 2.0
    var redGain: Float = 1.0      // 0.5 – 1.5
    var greenGain: Float = 1.0
    var blueGain: Float = 1.0

    static let `default` = ColorCalibration()

    // Vivid — punchy colors for action games (PUBG, CoD)
    static let vivid = ColorCalibration(
        brightness: 1.05,
        contrast: 1.1,
        saturation: 1.3,
        redGain: 1.0,
        greenGain: 1.0,
        blueGain: 0.95
    )

    // Cinema — accurate colors for RPGs (Genshin, HSR)
    static let cinema = ColorCalibration(
        brightness: 1.0,
        contrast: 1.05,
        saturation: 1.1,
        redGain: 1.0,
        greenGain: 1.0,
        blueGain: 1.02
    )
}

// Makes the VZVirtioGraphicsDeviceConfiguration for the VM
func makeGraphicsDevice(display: DisplayConfig) -> VZVirtioGraphicsDeviceConfiguration {
    let scanout = VZVirtioGraphicsScanoutConfiguration(
        widthInPixels: display.widthPx,
        heightInPixels: display.heightPx
    )
    let device = VZVirtioGraphicsDeviceConfiguration()
    device.scanouts = [scanout]
    return device
}

// VMWindow: an NSWindow that hosts the VZVirtualMachineView + Metal calibration overlay
@MainActor
class VMWindow: NSObject {
    private var window: NSWindow?
    private var vmView: VZVirtualMachineView?
    private let displayConfig: DisplayConfig

    init(displayConfig: DisplayConfig) {
        self.displayConfig = displayConfig
    }

    @MainActor
    func show(vm: VZVirtualMachine) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let logicalW = CGFloat(displayConfig.widthPx) / scale
        let logicalH = CGFloat(displayConfig.heightPx) / scale

        let rect = NSRect(x: 0, y: 0, width: logicalW, height: logicalH)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "nunu"
        win.center()
        win.isReleasedWhenClosed = false

        let view = VZVirtualMachineView()
        view.virtualMachine = vm
        view.capturesSystemKeys = true
        view.frame = rect
        view.autoresizingMask = [.width, .height]

        win.contentView = view
        win.makeKeyAndOrderFront(nil)

        self.window = win
        self.vmView = view
    }

    // Called by FramePacer on each vsync tick — asks the VM view to
    // present the latest framebuffer in sync with the display refresh
    func requestFrame() {
        vmView?.needsDisplay = true
    }
}
