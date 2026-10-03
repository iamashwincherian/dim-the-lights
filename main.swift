import AppKit

// Overlay sits above the Dock (20), below the menu bar (24), so the menu bar and its menus stay bright.
let overlayLevel = Int(CGWindowLevelForKey(.mainMenuWindow)) - 1
// Calibration knob: macOS window corner radii vary by window style; tune if corners look off.
let cornerRadius: CGFloat = 12

enum Mode: Int { case off, blur, dim }
enum Tint: Int, CaseIterable {
    case none, dark, light, accent
    var title: String { ["None", "Dark", "Light", "Accent"][rawValue] }
}

// Whole screen minus the focused window (even-odd fill).
func cutout(_ bounds: NSRect, _ hole: NSRect) -> NSBezierPath {
    let path = NSBezierPath(rect: bounds)
    if !hole.isEmpty { path.append(NSBezierPath(roundedRect: hole, xRadius: cornerRadius, yRadius: cornerRadius)) }
    path.windingRule = .evenOdd
    return path
}

final class DimView: NSView {
    var hole = NSRect.zero { didSet { if hole != oldValue { needsDisplay = true } } }
    var color = NSColor.black.withAlphaComponent(0.75) { didSet { if color != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        cutout(bounds, hole).fill()
    }
}

final class BlurView: NSVisualEffectView {
    var hole = NSRect.zero {
        didSet {
            guard hole != oldValue else { return }
            maskImage = NSImage(size: bounds.size, flipped: false) { [bounds, hole] _ in
                NSColor.black.setFill()
                cutout(bounds, hole).fill()
                return true
            }
        }
    }
}

// Off / Blur / Dim as three cards, styled after the reference design; lives inside the native menu.
final class CardPicker: NSView {
    let titles = ["Off", "Blur", "Dim"], icons = ["sun.max", "drop.halffull", "moon"]
    let accent = NSColor.controlAccentColor
    var selected: Int { didSet { needsDisplay = true } }
    let onChange: (Int) -> Void

    init(width: CGFloat, selected: Int, onChange: @escaping (Int) -> Void) {
        self.selected = selected
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 70))
    }
    required init?(coder: NSCoder) { fatalError() }

    func card(_ i: Int) -> NSRect {
        let w = (bounds.width - 28 - 16) / 3
        return NSRect(x: 14 + CGFloat(i) * (w + 8), y: 6, width: w, height: bounds.height - 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        for i in titles.indices {
            let on = i == selected, r = card(i)
            let shape = NSBezierPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), xRadius: 10, yRadius: 10)
            (on ? accent.withAlphaComponent(0.16) : NSColor.labelColor.withAlphaComponent(0.05)).setFill()
            shape.fill()
            (on ? accent : NSColor.labelColor.withAlphaComponent(0.12)).setStroke()
            shape.lineWidth = on ? 1.5 : 1
            shape.stroke()

            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                .applying(.init(paletteColors: [on ? accent : .secondaryLabelColor]))
            if let icon = NSImage(systemSymbolName: icons[i], accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                icon.draw(at: NSPoint(x: r.minX + 10, y: r.maxY - 10 - icon.size.height), from: .zero, operation: .sourceOver, fraction: 1)
            }
            (titles[i] as NSString).draw(at: NSPoint(x: r.minX + 10, y: r.minY + 8), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: on ? .semibold : .regular),
                .foregroundColor: on ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])
            if on {
                accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: r.maxX - 12, y: r.maxY - 12, width: 5, height: 5)).fill()
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = titles.indices.first(where: { card($0).contains(p) }), i != selected else { return }
        selected = i
        onChange(i)
    }
}

@MainActor final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let label = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let sliderItem = NSMenuItem()
    let tintItem = NSMenuItem(title: "Tint", action: nil, keyEquivalent: "")
    let defaults = UserDefaults.standard
    var overlays: [(window: NSWindow, dim: DimView, blur: BlurView)] = []
    var timer: Timer?
    var mode: Mode { Mode(rawValue: defaults.integer(forKey: "mode")) ?? .dim }
    var tint: Tint { Tint(rawValue: defaults.integer(forKey: "tint")) ?? .none }

    func applicationDidFinishLaunching(_ note: Notification) {
        defaults.register(defaults: ["mode": Mode.dim.rawValue, "strength": 0.75])
        item.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Dim the Lights")

        let pickerItem = NSMenuItem()
        pickerItem.view = CardPicker(width: 240, selected: mode.rawValue) { [weak self] i in
            self?.defaults.set(i, forKey: "mode")
            self?.apply()
        }

        let slider = NSSlider(value: defaults.double(forKey: "strength"), minValue: 0.1, maxValue: 0.95,
                              target: self, action: #selector(sliderChanged))
        slider.frame = NSRect(x: 18, y: 2, width: 204, height: 20)
        sliderItem.view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        sliderItem.view?.addSubview(slider)

        tintItem.submenu = NSMenu()
        for t in Tint.allCases {
            let i = NSMenuItem(title: t.title, action: #selector(tintChanged), keyEquivalent: "")
            i.target = self
            i.tag = t.rawValue
            tintItem.submenu?.addItem(i)
        }

        let menu = NSMenu()
        menu.items = [pickerItem, label, sliderItem, tintItem, .separator(),
                      NSMenuItem(title: "Quit Dim the Lights", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")]
        item.menu = menu

        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuild()
    }

    @objc func tintChanged(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: "tint")
        apply()
    }

    @objc func sliderChanged(_ slider: NSSlider) {
        defaults.set(slider.doubleValue, forKey: "strength")
        apply()
    }

    // One overlay per display, recreated when displays change.
    @objc func rebuild() {
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: overlayLevel)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let box = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let d = DimView(frame: box.bounds), b = BlurView(frame: box.bounds)
            b.material = .fullScreenUI
            b.blendingMode = .behindWindow
            b.state = .active
            for v in [b, d] { v.autoresizingMask = [.width, .height]; box.addSubview(v) }
            w.contentView = box
            return (w, d, b)
        }
        apply()
    }

    func apply() {
        let mode = mode
        let strength = defaults.double(forKey: "strength")
        label.title = "\(mode == .blur ? "Blur" : "Dimness"): \(Int((strength * 100).rounded()))%"
        label.isHidden = mode == .off
        sliderItem.isHidden = mode == .off
        tintItem.isHidden = mode != .blur
        tintItem.submenu?.items.forEach { $0.state = $0.tag == tint.rawValue ? .on : .off }
        // Blur tint = forced light/dark material + a soft color wash drawn by the dim layer.
        let wash: NSColor = switch tint {
            case .none: .clear
            case .dark: .black.withAlphaComponent(0.35 * strength)
            case .light: .white.withAlphaComponent(0.35 * strength)
            case .accent: .controlAccentColor.withAlphaComponent(0.35 * strength)
        }
        let look: NSAppearance? = switch tint {
            case .dark: NSAppearance(named: .darkAqua)
            case .light: NSAppearance(named: .aqua)
            default: nil
        }
        item.button?.appearsDisabled = mode == .off
        for o in overlays {
            o.dim.color = mode == .dim ? .black.withAlphaComponent(strength) : wash
            o.dim.isHidden = mode == .off || (mode == .blur && tint == .none)
            o.blur.appearance = look
            // ponytail: blur "strength" is the blur layer's opacity (no public radius API); private CAFilter if you want true radius.
            o.blur.alphaValue = strength
            o.blur.isHidden = mode != .blur
            if mode == .off { o.window.orderOut(nil) } else { o.window.orderFrontRegardless() }
        }
        timer?.invalidate()
        timer = nil
        guard mode != .off else { return }
        // ponytail: polls window bounds at 30Hz (hole lags slightly while dragging); AX observers if that bothers you.
        let t = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    // Find the frontmost app's topmost visible window and cut it out of every overlay.
    @objc func tick() {
        // When we're frontmost (launch, panel open), keep the topmost window of whatever app is underneath.
        let me = getpid()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? me
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []

        var hole = NSRect.zero
        for info in list {   // front-to-back order
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  frontPID == me || pid == frontPID,
                  let layer = info[kCGWindowLayer as String] as? Int, (0..<overlayLevel).contains(layer),
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict), r.width > 40, r.height > 40 else { continue }
            // CG coords are top-left origin on the primary display; Cocoa is bottom-left.
            hole = NSRect(x: r.minX, y: NSScreen.screens[0].frame.height - r.maxY, width: r.width, height: r.height)
            break
        }
        for o in overlays {
            let local = hole.isEmpty ? .zero : hole.offsetBy(dx: -o.window.frame.minX, dy: -o.window.frame.minY)
            o.dim.hole = local
            o.blur.hole = local
        }
    }
}

MainActor.assumeIsolated {
    let delegate = App()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
