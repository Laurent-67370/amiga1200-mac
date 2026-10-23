import AppKit
import GameController
import QuartzCore

/// Démarrage du cœur dans ce processus : journal, dossiers, options de la version web, bruits des lecteurs
enum Core {
    static func start(_ content: String) -> Bool {
        Paths.installResources()
        amb_set_log(Paths.log.path)
        amb_log("amiga1200-mac \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        amb_log("Contenu : \(content)")
        // Bruits des lecteurs : le cœur cherche data/floppy_sounds dans AMIBERRY_DATA_DIR
        setenv("AMIBERRY_DATA_DIR", Paths.data.path, 1)
        amb_set_dirs(Paths.sys.path, Paths.save.path)
        amb_set_option("amiberry_crop_overscan", "enabled")
        amb_set_option("amiberry_statusline", "disabled")
        amb_set_option("amiberry_joyport_order", "21")
        return amb_start(content) != 0
    }
}

/// Fenêtre de l'émulation (processus lancé par l'accueil avec --emu) : l'image, le clavier, la souris, les manettes
final class EmuDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let content: String
    var window: NSWindow!
    var view: EmuView!
    var paused = false, turbo = false
    var statsTimer: Timer?

    init(content: String) { self.content = content }

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        view = EmuView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Amiga 1200 — démarrage…"
        window.contentView = view
        window.contentMinSize = NSSize(width: 400, height: 300)
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        Gamepads.shared.start()
        if !Core.start(content) { fail("le fil de l'émulation n'a pas pu démarrer"); return }
        let t0 = Date()
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            switch amb_state() {
            case 2:
                t.invalidate()
                self.view.startDisplay()
                self.statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.stats() }
            case 1:
                if Date().timeIntervalSince(t0) > 60 { t.invalidate(); self.fail("le cœur ne répond pas") }
            default:
                t.invalidate(); self.fail("le cœur a refusé la configuration (Kickstart ou disque illisible ?)")
            }
        }
    }

    func fail(_ why: String) {
        let a = NSAlert()
        a.messageText = "Démarrage impossible"
        a.informativeText = why + "\n\nLe journal est dans ~/Library/Application Support/Amiga1200/journal.txt."
        a.runModal()
        NSApp.terminate(nil)
    }

    func stats() {
        let n = amb_frames(), busy = amb_busy_us()
        let fps = amb_fps() > 0 ? amb_fps() : 50
        let jit = Settings.shared.jit && Settings.bigBox(Settings.shared.model) && !Settings.isWhd(content) ? " · JIT" : ""
        let what = paused ? "en pause" : turbo ? "turbo : \(n) images/s" :
            String(format: "%d images/s · %d %% · %.1f ms/image", n, Int(Double(n) * 100 / fps), n > 0 ? busy / Double(n) / 1000 : 0)
        window.title = "Amiga 1200 — \(what)\(jit)" + (view.captured ? "  (⌥⌘ ou F12 : libérer la souris)" : "  (cliquez pour capturer la souris)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) {
        // Image du jeu pour la Bibliothèque, s'il n'en a pas encore
        if amb_state() == 2, let g = gameName { _ = Captures.save(name: g, gallery: false, onlyIfMissing: true) }
        amb_stop()
        usleep(200_000)   // écriture des disques
    }
    func windowDidResignKey(_ n: Notification) { view.release() }

    // ---------- menu ----------
    func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Quitter l'Amiga", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let amiItem = NSMenuItem(); bar.addItem(amiItem)
        let m = NSMenu(title: "Amiga")
        func add(_ t: String, _ s: Selector, _ k: String, _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: t, action: s, keyEquivalent: k); i.keyEquivalentModifierMask = mods; i.target = self; m.addItem(i)
        }
        add("Pause", #selector(togglePause), "p")
        add("Sauvegarde rapide", #selector(quickSave), "s")
        add("Reprise rapide", #selector(quickLoad), "l")
        m.addItem(.separator())
        add("Disquette DF0:…", #selector(insertDF0), "o")
        add("Disquette DF1:…", #selector(insertDF1), "o", [.command, .shift])
        add("Éjecter DF0:", #selector(ejectDF0), "")
        m.addItem(.separator())
        add("Image nette ou lisse", #selector(toggleSharp), "i")
        add("Plein écran", #selector(fullScreen), "f", [.command, .control])
        add("Capture d'écran", #selector(capture), "k")
        add("Bruit des lecteurs", #selector(toggleFloppySound), "")
        add("Turbo", #selector(toggleTurbo), "t")
        add("Journal", #selector(openLog), "")
        m.addItem(.separator())
        add("Réinitialiser (redémarrage à froid)", #selector(restart), "r")
        amiItem.submenu = m
        NSApp.mainMenu = bar
    }

    @objc func togglePause() { paused.toggle(); amb_pause(paused ? 1 : 0); stats() }
    @objc func toggleTurbo() { turbo.toggle(); amb_turbo(turbo ? 1 : 0) }
    @objc func quickSave() { flash(amb_save_state(Paths.save.appendingPathComponent("etat-\(Settings.shared.model)-1.uss").path) != 0 ? "État sauvegardé" : "Sauvegarde impossible") }
    @objc func quickLoad() {
        let f = Paths.save.appendingPathComponent("etat-\(Settings.shared.model)-1.uss")
        flash(FileManager.default.fileExists(atPath: f.path) && amb_load_state(f.path) != 0 ? "État repris" : "Aucun état à reprendre")
    }
    @objc func insertDF0() { insert(0) }
    @objc func insertDF1() { insert(1) }
    @objc func ejectDF0() { amb_insert_disk(0, ""); flash("DF0: éjectée") }
    func insert(_ drive: Int32) {
        view.release()
        let p = NSOpenPanel()
        p.message = "Disquette pour DF\(drive): (ADF, DMS, IPF…)"
        if p.runModal() == .OK, let u = p.url {
            amb_insert_disk(drive, u.path)
            if drive == 0 { Settings.shared.df0 = u.path } else { Settings.shared.df1 = u.path }
            flash("DF\(drive): \(u.lastPathComponent)")
        }
    }
    @objc func toggleSharp() { Settings.shared.sharp.toggle(); view.applyFilter() }
    @objc func fullScreen() { window.toggleFullScreen(nil) }
    @objc func toggleFloppySound() {
        Settings.shared.floppySound.toggle(); amb_floppy_sound(Settings.shared.floppySound ? 1 : 0)
        flash(Settings.shared.floppySound ? "Bruit des lecteurs" : "Lecteurs silencieux")
    }
    /// Jeu en cours (son image dans la Bibliothèque) : l'archive WHDLoad, sinon la disquette DF0:, sinon le premier disque dur
    var gameName: String? {
        if Settings.isWhd(content) { return (content as NSString).lastPathComponent }
        let s = Settings.shared
        let p = !s.df0.isEmpty ? s.df0 : s.hds.first ?? ""
        return p.isEmpty ? nil : (p as NSString).lastPathComponent
    }
    @objc func capture() {
        let ok = Captures.save(name: gameName ?? "Amiga", gallery: true)
        flash(ok ? "Capture enregistrée (Images/Amiga1200 et Bibliothèque)" : "Capture impossible")
    }
    @objc func openLog() { NSWorkspace.shared.open(Paths.log) }
    /// Le cœur ne se rallume pas dans le même processus : un nouveau processus prend la suite
    @objc func restart() {
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--emu", content]
        try? p.run()
        NSApp.terminate(nil)
    }
    func flash(_ t: String) { window.title = "Amiga 1200 — \(t)" }
}

/// Image de l'Amiga (Core Animation) et entrées clavier et souris
final class EmuView: NSView {
    private var lastFrame: UInt = 0
    private var timer: Timer?
    private var downMods = Set<UInt16>()
    private var buttons: Int32 = 0
    private var accX = 0.0, accY = 0.0
    private(set) var captured = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        applyFilter()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func applyFilter() {
        let f: CALayerContentsFilter = Settings.shared.sharp ? .nearest : .linear
        layer?.magnificationFilter = f
        layer?.minificationFilter = .linear
    }

    func startDisplay() {
        timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.draw() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Nouvelle image du cœur : copiée dans une image Core Graphics, affichée par la couche de la vue
    private func draw() {
        let fc = UInt(amb_frame_count())
        if fc == lastFrame { return }
        lastFrame = fc
        var w: UInt32 = 0, h: UInt32 = 0
        guard let p = amb_frame(&w, &h), w > 0, h > 0,
              let data = CFDataCreate(nil, p, Int(w) * Int(h) * 4),
              let prov = CGDataProvider(data: data),
              let img = CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(w) * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = img
        CATransaction.commit()
    }

    // ---------- souris : capturée d'un clic, libérée par ⌥⌘ ou F12 ----------
    private func capture() {
        if captured { return }
        captured = true
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }
    func release() {
        if !captured { return }
        captured = false
        buttons = 0; amb_mouse_buttons(0)
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }
    private func moved(_ e: NSEvent) {
        guard captured else { return }
        accX += Double(e.deltaX); accY += Double(e.deltaY)
        let dx = Int32(accX.rounded(.towardZero)), dy = Int32(accY.rounded(.towardZero))
        accX -= Double(dx); accY -= Double(dy)
        if dx != 0 || dy != 0 { amb_mouse_move(dx, dy) }
    }
    private func button(_ bit: Int32, _ down: Bool) {
        buttons = down ? buttons | bit : buttons & ~bit
        amb_mouse_buttons(buttons)
    }
    override func mouseDown(with e: NSEvent) { if !captured { capture(); return }; button(1, true) }
    override func mouseUp(with e: NSEvent) { if captured { button(1, false) } }
    override func rightMouseDown(with e: NSEvent) { if captured { button(2, true) } }
    override func rightMouseUp(with e: NSEvent) { if captured { button(2, false) } }
    override func otherMouseDown(with e: NSEvent) { if captured { button(4, true) } }
    override func otherMouseUp(with e: NSEvent) { if captured { button(4, false) } }
    override func mouseMoved(with e: NSEvent) { moved(e) }
    override func mouseDragged(with e: NSEvent) { moved(e) }
    override func rightMouseDragged(with e: NSEvent) { moved(e) }
    override func otherMouseDragged(with e: NSEvent) { moved(e) }

    // ---------- clavier ----------
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 111 { release(); return }          // F12 : libère la souris
        if e.isARepeat { return }
        if let k = Keymap.retrok(e.keyCode) { amb_key(1, k) }
    }
    override func keyUp(with e: NSEvent) {
        if let k = Keymap.retrok(e.keyCode) { amb_key(0, k) }
    }
    /// Raccourcis ⌘ : ceux du menu tant que la souris est libre ; souris capturée, tout va à l'Amiga
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard captured else { return super.performKeyEquivalent(with: e) }
        if e.type == .keyDown { keyDown(with: e) } else if e.type == .keyUp { keyUp(with: e) }
        return true
    }
    override func flagsChanged(with e: NSEvent) {
        let flags = e.modifierFlags
        if flags.contains(.command) && flags.contains(.option) { release() }
        guard Keymap.modifiers.contains(e.keyCode), let k = Keymap.retrok(e.keyCode) else { return }
        if e.keyCode == 57 { amb_key(1, k); amb_key(0, k); return }   // Verr. maj. : un appui à chaque bascule
        if downMods.contains(e.keyCode) { downMods.remove(e.keyCode); amb_key(0, k) }
        else { downMods.insert(e.keyCode); amb_key(1, k) }
    }
}

/// Manettes (Game Controller) : la première joue sur le port joystick, la deuxième sur le port souris
final class Gamepads {
    static let shared = Gamepads()
    private var players: [ObjectIdentifier: Int32] = [:]

    func start() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { self?.attach(c) }
        }
        GCController.controllers().forEach(attach)
    }

    private func attach(_ c: GCController) {
        let id = ObjectIdentifier(c)
        if players[id] != nil { return }
        let player = Int32(min(players.count, 1))
        players[id] = player
        c.extendedGamepad?.valueChangedHandler = { gp, _ in
            var m: UInt32 = 0
            let x = gp.leftThumbstick.xAxis.value, y = gp.leftThumbstick.yAxis.value
            if gp.dpad.up.isPressed || y > 0.5 { m |= 1 << 4 }
            if gp.dpad.down.isPressed || y < -0.5 { m |= 1 << 5 }
            if gp.dpad.left.isPressed || x < -0.5 { m |= 1 << 6 }
            if gp.dpad.right.isPressed || x > 0.5 { m |= 1 << 7 }
            if gp.buttonA.isPressed { m |= 1 << 0 }        // tir
            if gp.buttonB.isPressed { m |= 1 << 8 }        // 2e bouton
            if gp.buttonX.isPressed { m |= 1 << 1 }
            if gp.buttonY.isPressed { m |= 1 << 9 }
            if gp.leftShoulder.isPressed { m |= 1 << 10 }
            if gp.rightShoulder.isPressed { m |= 1 << 11 }
            if gp.buttonMenu.isPressed { m |= 1 << 3 }
            if gp.buttonOptions?.isPressed == true { m |= 1 << 2 }
            amb_joy(player, m)
        }
    }
}
