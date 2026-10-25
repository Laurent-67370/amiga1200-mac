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
        // MIDI du port série vers CoreMIDI (MidiLink)
        amb_set_option("amiberry_midi_output", Settings.shared.midi ? "libretro" : "disabled")
        // Jeu WHDLoad dans une archive autre que .lha (dossier zippé, .lzx…) : le cœur la lance comme une .lha
        amb_set_option("amiberry_whdload_archive", ["zip", "7z", "lzx"].contains((content as NSString).pathExtension.lowercased()) ? "enabled" : "disabled")
        return amb_start(content) != 0
    }
}

/// Fenêtre de l'émulation (processus lancé par l'accueil avec --emu) : l'image, le clavier, la souris, les manettes
final class EmuDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let content: String
    /// Lancé par « Reprendre où j'en étais » : l'état gardé est rechargé une fois l'Amiga allumé
    let resume: Bool
    var restarting = false
    var statesPanel: SaveStatesPanel?
    var window: NSWindow!
    var view: EmuView!
    var paused = false, turbo = false
    var statsTimer: Timer?
    var midi: MidiLink?
    /// Quatre lecteurs de disquettes branchés (DF2: ou DF3: utilisés au démarrage)
    let fourDrives = !Settings.shared.df2.isEmpty || !Settings.shared.df3.isEmpty

    init(content: String, resume: Bool = false) { self.content = content; self.resume = resume }

    func applicationDidFinishLaunching(_ n: Notification) {
        CrashReport.started()
        buildMenu()
        view = EmuView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
        view.game = stateKey
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
        Gamepads.shared.keyMap = PadKeys.load(stateKey)
        Gamepads.shared.start()
        if !Core.start(content) { fail("le fil de l'émulation n'a pas pu démarrer"); return }
        let t0 = Date()
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            switch amb_state() {
            case 2:
                t.invalidate()
                self.view.startDisplay()
                if Settings.shared.midi {
                    let m = MidiLink(); self.midi = m
                    let msg = m.start(Settings.shared)
                    amb_log(msg); self.flash(msg)
                }
                if self.resume {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        let f = Settings.resumeFile
                        let ok = FileManager.default.fileExists(atPath: f.path) && amb_load_state(f.path) != 0
                        try? FileManager.default.removeItem(at: f)
                        self.flash(ok ? "Reprise où vous en étiez" : "Reprise impossible, l'Amiga redémarre normalement")
                    }
                } else { try? FileManager.default.removeItem(at: Settings.resumeFile) }   // les disques changent : l'ancien état ne vaut plus
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
        let jit = Settings.shared.jit && Settings.bigBox(Settings.shared.model) && content.hasSuffix("amiga.uae") ? " · JIT" : ""
        let what = paused ? "en pause" : turbo ? "turbo : \(n) images/s" :
            String(format: "%d images/s · %d %% · %.1f ms/image", n, Int(Double(n) * 100 / fps), n > 0 ? busy / Double(n) / 1000 : 0)
        window.title = "Amiga 1200 — \(what)\(jit)" + (view.captured ? "  (⌥⌘ ou F12 : libérer la souris)" : "  (cliquez pour capturer la souris)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) {
        // Image du jeu pour la Bibliothèque, s'il n'en a pas encore
        if amb_state() == 2, let g = gameName { _ = Captures.save(name: g, gallery: false, onlyIfMissing: true) }
        // « Reprendre où j'en étais » : l'état est gardé, avec ce qu'il faut pour rallumer la même chose (machine ou jeu)
        if amb_state() == 2 && !restarting && amb_save_state(Settings.resumeFile.path) != 0 {
            let s = Settings.shared
            s.resumeSig = s.signature()
            let env = ProcessInfo.processInfo.environment
            if !content.hasSuffix(".uae") { s.resumeGame = "whd\n\(content)\n\((content as NSString).lastPathComponent)" }
            else if let h = env["AMIGA1200_HDF"] { s.resumeGame = "hdf\n\(h)\n\(env["AMIGA1200_JEU"] ?? (h as NSString).lastPathComponent)" }
            else { s.resumeGame = "" }
        }
        midi?.stop()
        amb_stop()
        usleep(200_000)   // écriture des disques
        CrashReport.ended()
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
        add("Sauvegardes d'état…", #selector(showStates), "e")
        m.addItem(.separator())
        add("Disquette DF0:…", #selector(insertDF0), "o")
        add("Disquette DF1:…", #selector(insertDF1), "o", [.command, .shift])
        if fourDrives {
            add("Disquette DF2:…", #selector(insertDF2), "")
            add("Disquette DF3:…", #selector(insertDF3), "")
        }
        let ej = NSMenu()
        for i in 0..<(fourDrives ? 4 : 2) {
            let it = NSMenuItem(title: "DF\(i):", action: #selector(eject(_:)), keyEquivalent: ""); it.tag = i; it.target = self; ej.addItem(it)
        }
        let ejItem = NSMenuItem(title: "Éjecter", action: nil, keyEquivalent: ""); ejItem.submenu = ej; m.addItem(ejItem)
        add("Disquette vierge…", #selector(blankDisk), "n")
        m.addItem(.separator())
        // Image : filtre et pixels réguliers
        let im = NSMenu()
        for (i, t) in ["Lisse", "Nette (pixels francs)", "Écran cathodique (lignes de balayage)"].enumerated() {
            let it = NSMenuItem(title: t, action: #selector(setFilter(_:)), keyEquivalent: ""); it.tag = i; it.target = self; im.addItem(it)
        }
        im.addItem(.separator())
        let integer = NSMenuItem(title: "Pixels réguliers (agrandissement entier)", action: #selector(toggleInteger), keyEquivalent: ""); integer.target = self; im.addItem(integer)
        let next = NSMenuItem(title: "Filtre suivant", action: #selector(nextFilter), keyEquivalent: "i"); next.target = self; im.addItem(next)
        im.addItem(.separator())
        let frame = NSMenuItem(title: "Image et cadrage de ce jeu…", action: #selector(showDisplay), keyEquivalent: "j"); frame.target = self; im.addItem(frame)
        imageMenu = im
        let imItem = NSMenuItem(title: "Image", action: nil, keyEquivalent: ""); imItem.submenu = im; m.addItem(imItem)
        updateImageMenu()
        add("Plein écran", #selector(fullScreen), "f", [.command, .control])
        add("Capture d'écran", #selector(capture), "k")
        add("Bruit des lecteurs", #selector(toggleFloppySound), "")
        add("Turbo", #selector(toggleTurbo), "t")
        add("Touches de la manette (ce jeu)…", #selector(editPadKeys), "")
        m.addItem(.separator())
        add("Quitter le jeu (touche de sortie de WHDLoad)", #selector(quitGame), ".")
        let qk = NSMenu()
        for (k, t) in EmuDelegate.quitKeys {
            let it = NSMenuItem(title: t, action: #selector(setQuitKey(_:)), keyEquivalent: ""); it.tag = k; it.target = self
            it.state = k == Settings.shared.quitKey ? .on : .off; qk.addItem(it)
        }
        let qkItem = NSMenuItem(title: "Touche de sortie", action: nil, keyEquivalent: ""); qkItem.submenu = qk; m.addItem(qkItem)
        add("Journal", #selector(openLog), "")
        m.addItem(.separator())
        add("Réinitialiser (redémarrage à froid)", #selector(restart), "r")
        amiItem.submenu = m
        NSApp.mainMenu = bar
    }

    @objc func togglePause() { paused.toggle(); amb_pause(paused ? 1 : 0); stats(); flash(paused ? "Pause" : "Reprise") }
    @objc func toggleTurbo() { turbo.toggle(); amb_turbo(turbo ? 1 : 0); flash(turbo ? "Turbo" : "Vitesse normale") }
    /// Emplacement 1 du jeu en cours (sinon de la machine)
    var stateKey: String { gameName ?? Settings.shared.model }
    @objc func quickSave() { flash(SaveStates.save(stateKey, 0) ? "État 1 sauvegardé" : "Sauvegarde impossible") }
    @objc func quickLoad() { flash(SaveStates.load(stateKey, 0) ? "État 1 repris" : "Aucun état à reprendre") }
    @objc func showStates() {
        view.release()
        statesPanel = SaveStatesPanel(game: stateKey) { [weak self] t in self?.flash(t) }
        statesPanel?.show(over: window)
    }
    @objc func insertDF0() { insert(0) }
    @objc func insertDF1() { insert(1) }
    @objc func insertDF2() { insert(2) }
    @objc func insertDF3() { insert(3) }
    @objc func eject(_ i: NSMenuItem) { amb_insert_disk(Int32(i.tag), ""); Settings.shared.setFloppy(i.tag, ""); flash("DF\(i.tag): éjectée") }
    /// Disquette formatée, pour les sauvegardes des jeux ou les données : créée puis mise dans DF1:
    @objc func blankDisk() {
        view.release()
        let p = NSSavePanel()
        p.message = "Disquette vierge formatée (880 Ko), mise dans DF1:"
        p.nameFieldStringValue = "Sauvegardes.adf"
        p.allowedFileTypes = ["adf"]
        guard p.runModal() == .OK, let u = p.url else { return }
        guard (try? BlankDisk.adf(u.deletingPathExtension().lastPathComponent).write(to: u)) != nil else { flash("Création de la disquette impossible"); return }
        Library.add(u.path)
        amb_insert_disk(1, u.path); Settings.shared.df1 = u.path
        flash("DF1: \(u.lastPathComponent) (vierge)")
    }
    func insert(_ drive: Int32) {
        view.release()
        let p = NSOpenPanel()
        p.message = "Disquette pour DF\(drive): (ADF, DMS, IPF…)"
        if p.runModal() == .OK, let u = p.url {
            amb_insert_disk(drive, u.path)
            Settings.shared.setFloppy(Int(drive), u.path)
            flash("DF\(drive): \(u.lastPathComponent)")
        }
    }
    var imageMenu: NSMenu?
    static let filterNames = ["Image lisse", "Image nette", "Écran cathodique"]
    @objc func setFilter(_ i: NSMenuItem) { applyFilter(i.tag) }
    @objc func nextFilter() { applyFilter((Settings.shared.filter + 1) % 3) }
    func applyFilter(_ f: Int) {
        Settings.shared.filter = f
        view.applyFilter(); updateImageMenu(); flash(EmuDelegate.filterNames[f])
    }
    @objc func toggleInteger() {
        Settings.shared.integer.toggle()
        view.applyFilter(); updateImageMenu()
        flash(Settings.shared.integer ? "Pixels réguliers" : "Image à la taille de la fenêtre")
    }
    func updateImageMenu() {
        for it in imageMenu?.items ?? [] {
            if it.action == #selector(setFilter(_:)) { it.state = it.tag == Settings.shared.filter ? .on : .off }
            if it.action == #selector(toggleInteger) { it.state = Settings.shared.integer ? .on : .off }
        }
    }
    @objc func editPadKeys() {
        view.release()
        let g = stateKey
        if let m = PadKeys.dialog(game: g, title: (g as NSString).deletingPathExtension) {
            Gamepads.shared.keyMap = m
            flash(m.isEmpty ? "Manette par défaut" : "Touches de la manette enregistrées pour ce jeu")
        }
    }
    // Touche de sortie des jeux WHDLoad
    static let quitKeys = [(291, "F10"), (268, "* du pavé numérique"), (27, "Échap")]
    @objc func quitGame() {
        let k = UInt32(Settings.shared.quitKey)
        amb_key(1, k)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { amb_key(0, k) }
        flash("Touche de sortie : " + (EmuDelegate.quitKeys.first { $0.0 == Int(k) }?.1 ?? "?"))
    }
    @objc func setQuitKey(_ i: NSMenuItem) {
        Settings.shared.quitKey = i.tag
        for it in i.menu?.items ?? [] { it.state = it.tag == i.tag ? .on : .off }
    }
    @objc func fullScreen() { window.toggleFullScreen(nil) }
    @objc func toggleFloppySound() {
        Settings.shared.floppySound.toggle(); amb_floppy_sound(Settings.shared.floppySound ? 1 : 0)
        flash(Settings.shared.floppySound ? "Bruit des lecteurs" : "Lecteurs silencieux")
    }
    /// Jeu en cours (son image dans la Bibliothèque) : l'archive WHDLoad, sinon la disquette DF0:, sinon le premier disque dur
    var gameName: String? {
        if !content.hasSuffix(".uae") { return (content as NSString).lastPathComponent }   // archive WHDLoad
        if let g = ProcessInfo.processInfo.environment["AMIGA1200_JEU"] { return g }       // jeu WHDLoad sur .hdf
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
        restarting = true
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--emu", content]
        try? p.run()
        NSApp.terminate(nil)
    }
    /// Message bref dans une bulle, sur l'image
    func flash(_ t: String) { view?.show(t) }
    var displayPanel: DisplayPanel?
    @objc func showDisplay() {
        view.release()
        displayPanel = DisplayPanel(game: stateKey) { [weak self] in self?.view.applyFilter(); self?.updateImageMenu() }
        displayPanel?.show(over: window)
    }
}

/// Image de l'Amiga (Core Animation) et entrées clavier et souris
final class EmuView: NSView {
    private var lastFrame: UInt = 0
    private var timer: Timer?
    private var downMods = Set<UInt16>()
    private var buttons: Int32 = 0
    private var accX = 0.0, accY = 0.0
    private(set) var captured = false
    /// Image de l'Amiga, et lignes de balayage par-dessus (écran cathodique)
    private let screen = CALayer(), scan = CALayer()
    private var imgW = 0, imgH = 0
    /// Jeu en cours : son cadrage (zoom, décalage vertical)
    var game = ""
    private let toast = NSTextField(labelWithString: "")
    private var toastSerial = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        screen.contentsGravity = .resize
        scan.contentsGravity = .resize
        scan.magnificationFilter = .nearest
        layer?.masksToBounds = true
        layer?.addSublayer(screen)
        layer?.addSublayer(scan)
        // Bulle des messages, en bas de l'image
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textColor = .white
        toast.alignment = .center
        toast.wantsLayer = true
        toast.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        toast.layer?.cornerRadius = 10
        toast.layer?.zPosition = 10
        toast.alphaValue = 0
        addSubview(toast)
        applyFilter()
    }

    /// Message bref : une bulle qui s'efface d'elle-même
    func show(_ text: String) {
        toastSerial += 1
        let serial = toastSerial
        toast.stringValue = "  " + text + "  "
        toast.sizeToFit()
        let w = min(toast.frame.width + 16, bounds.width - 20), h = toast.frame.height + 12
        toast.frame = NSRect(x: ((bounds.width - w) / 2).rounded(), y: 24, width: w, height: h)
        toast.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, serial == self.toastSerial else { return }
            NSAnimationContext.runAnimationGroup { c in c.duration = 0.4; self.toast.animator().alphaValue = 0 }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Filtre : lisse, net (pixels francs) ou écran cathodique (pixels francs et une ligne sur deux assombrie)
    func applyFilter() {
        let f = Settings.shared.filter
        screen.magnificationFilter = f == 0 ? .linear : .nearest
        screen.minificationFilter = .linear
        scan.isHidden = f != 2 || imgH == 0
        if f == 2 && imgH > 0 { scan.contents = EmuView.scanlines(imgH) }
        frameScreen()
    }

    /// Une colonne de pixels : une ligne sur deux assombrie de 35 %
    private static func scanlines(_ h: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: 1, height: h, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        for y in stride(from: 0, to: h, by: 2) { ctx.fill(CGRect(x: 0, y: y, width: 1, height: 1)) }
        return ctx.makeImage()
    }

    override func layout() { super.layout(); frameScreen() }

    /// Image en 4:3 centrée, ou sur toute la fenêtre ; pixels réguliers : le plus grand multiple entier qui tient dans la
    /// fenêtre ; puis le cadrage du jeu (zoom et décalage vertical)
    func frameScreen() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let b = bounds
        guard imgW > 0, imgH > 0, b.width > 0, b.height > 0 else { screen.frame = b; scan.frame = b; return }
        let s = Settings.shared
        let iw = CGFloat(imgW), ih = CGFloat(imgH)
        var w = b.width, h = b.height
        if s.integer {
            let sf = window?.backingScaleFactor ?? 2
            let k = floor(min(b.width * sf / iw, b.height * sf / ih))
            if k >= 1 { w = iw * k / sf; h = ih * k / sf } else { h = min(b.height, b.width * ih / iw); w = h * iw / ih }
        } else if !s.fill {
            if b.width * 3 > b.height * 4 { w = b.height * 4 / 3 } else { h = b.width * 3 / 4 }
        }
        let zoom = CGFloat(game.isEmpty ? 1 : s.zoom(game)), shift = CGFloat(game.isEmpty ? 0 : s.shiftY(game))
        w *= zoom; h *= zoom
        // Décalage vers le bas pour une valeur positive (la couche a son origine en bas)
        screen.frame = CGRect(x: ((b.width - w) / 2).rounded(), y: ((b.height - h) / 2 - shift * h).rounded(), width: w, height: h)
        scan.frame = screen.frame
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
        screen.contents = img
        CATransaction.commit()
        if Int(w) != imgW || Int(h) != imgH { imgW = Int(w); imgH = Int(h); applyFilter() }
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
    /// Boutons changés en touches du clavier pour le jeu en cours, et ceux qui tiennent leur touche enfoncée
    var keyMap: [String: Int] = [:]
    private var held: [ObjectIdentifier: Set<String>] = [:]

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
        c.extendedGamepad?.valueChangedHandler = { [weak self] gp, _ in
            guard let self else { return }
            var m: UInt32 = 0
            // Boutons réglés en touches du clavier : un appui, un relâchement
            let pressed: [String: Bool] = [
                "X": gp.buttonX.isPressed, "Y": gp.buttonY.isPressed, "L1": gp.leftShoulder.isPressed, "R1": gp.rightShoulder.isPressed,
                "L2": gp.leftTrigger.isPressed, "R2": gp.rightTrigger.isPressed,
                "L3": gp.leftThumbstickButton?.isPressed == true, "R3": gp.rightThumbstickButton?.isPressed == true,
                "Menu": gp.buttonMenu.isPressed, "Options": gp.buttonOptions?.isPressed == true,
            ]
            var h = self.held[id] ?? []
            for (b, k) in self.keyMap {
                let down = pressed[b] == true
                if down != h.contains(b) {
                    amb_key(down ? 1 : 0, UInt32(k))
                    if down { h.insert(b) } else { h.remove(b) }
                }
            }
            for b in h where self.keyMap[b] == nil { h.remove(b) }
            self.held[id] = h
            func joy(_ b: String) -> Bool { self.keyMap[b] == nil && pressed[b] == true }
            let x = gp.leftThumbstick.xAxis.value, y = gp.leftThumbstick.yAxis.value
            if gp.dpad.up.isPressed || y > 0.5 { m |= 1 << 4 }
            if gp.dpad.down.isPressed || y < -0.5 { m |= 1 << 5 }
            if gp.dpad.left.isPressed || x < -0.5 { m |= 1 << 6 }
            if gp.dpad.right.isPressed || x > 0.5 { m |= 1 << 7 }
            if gp.buttonA.isPressed { m |= 1 << 0 }        // tir
            if gp.buttonB.isPressed { m |= 1 << 8 }        // 2e bouton
            if joy("X") { m |= 1 << 1 }
            if joy("Y") { m |= 1 << 9 }
            if joy("L1") { m |= 1 << 10 }
            if joy("R1") { m |= 1 << 11 }
            if joy("Menu") { m |= 1 << 3 }
            if joy("Options") { m |= 1 << 2 }
            amb_joy(player, m)
        }
    }
}
