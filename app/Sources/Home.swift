import AppKit

/// Écran d'accueil : Kickstart, disques, machine, préréglages, bouton « Allumer » (même rôle que l'accueil Android).
/// L'émulation tourne dans un second processus (le cœur garde un état global) : l'accueil reste ouvert.
final class HomeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let s = Settings.shared
    var summary = NSTextField(labelWithString: "")
    var romLabel = NSTextField(labelWithString: "")
    var df0Label = NSTextField(labelWithString: "")
    var df1Label = NSTextField(labelWithString: "")
    var hdLabel = NSTextField(wrappingLabelWithString: "")
    var modelPopup = NSPopUpButton()
    var checks: [(NSButton, () -> Bool)] = []
    let libTabs = NSSegmentedControl(labels: ["🎮 Jeux WHDLoad", "💾 Disquettes", "🗄 Disques durs"], trackingMode: .selectOne, target: nil, action: nil)
    let libList = NSStackView()
    var libKind = Library.whd

    func applicationDidFinishLaunching(_ n: Notification) {
        Paths.installResources()
        buildMenu()
        let col = NSStackView()
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 10
        col.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)

        let title = NSTextField(labelWithString: "Amiga 1200")
        title.font = .boldSystemFont(ofSize: 26); title.textColor = .systemOrange
        col.addArrangedSubview(title)
        summary.textColor = .secondaryLabelColor
        col.addArrangedSubview(summary)

        col.addArrangedSubview(section("⚡ Préréglages"))
        col.addArrangedSubview(row([
            button("AGS / Workbench") { [self] in s.model = "A1200"; s.jit = true; s.rtg = true; refresh() },
            button("A1200 d'origine") { [self] in s.model = "A1200"; s.jit = false; s.rtg = false; refresh() },
            button("Amiga 500") { [self] in s.model = "A500"; s.jit = false; s.rtg = false; refresh() },
        ]))

        col.addArrangedSubview(section("📚 Bibliothèque"))
        libTabs.target = self; libTabs.action = #selector(libTab)
        col.addArrangedSubview(libTabs)
        libList.orientation = .vertical; libList.alignment = .leading; libList.spacing = 4
        col.addArrangedSubview(libList)
        col.addArrangedSubview(row([button("Ajouter des fichiers…") { [self] in addFiles(pickMany("Jeux WHDLoad (.lha), disquettes, disques durs (.hdf) ou Kickstart", multiple: true)) }]))
        col.addArrangedSubview(note("Glissez aussi vos fichiers sur cette fenêtre depuis le Finder. Un jeu WHDLoad se lance d'un clic ; un Kickstart glissé ici est installé comme ROM de la machine."))

        col.addArrangedSubview(section("🔑 Kickstart"))
        col.addArrangedSubview(romLabel)
        col.addArrangedSubview(row([
            button("Choisir un fichier…") { [self] in chooseRom() },
            button("AROS (libre)") { [self] in s.rom = "aros"; refresh() },
        ]))

        col.addArrangedSubview(section("💾 Disques"))
        col.addArrangedSubview(df0Label)
        col.addArrangedSubview(row([
            button("DF0:…") { [self] in if let p = pick("Disquette DF0: (ADF, DMS, IPF…) ou jeu WHDLoad (.lha)") { Library.add(p); s.df0 = p; refresh() } },
            button("Éjecter DF0:") { [self] in s.df0 = ""; refresh() },
            button("DF1:…") { [self] in if let p = pick("Disquette DF1:") { Library.add(p); s.df1 = p; refresh() } },
            button("Éjecter DF1:") { [self] in s.df1 = ""; refresh() },
        ]))
        col.addArrangedSubview(df1Label)
        col.addArrangedSubview(hdLabel)
        col.addArrangedSubview(row([
            button("Ajouter des disques durs…") { [self] in addHds() },
            button("Retirer les disques durs") { [self] in s.hds = []; refresh() },
        ]))
        col.addArrangedSubview(note("Un jeu WHDLoad (.lha) mis dans DF0: se lance seul. Pour AGS, ajoutez tous ses .hdf d'un coup (Workbench.hdf passe en premier)."))

        col.addArrangedSubview(section("⚙️ Machine"))
        modelPopup.addItems(withTitles: ["A500", "A600", "A1200", "A4000"])
        modelPopup.target = self; modelPopup.action = #selector(modelChanged)
        col.addArrangedSubview(modelPopup)
        col.addArrangedSubview(check("JIT 68040 : beaucoup plus rapide (A1200, A4000)", { [self] in s.jit }) { [self] in s.jit = $0 })
        col.addArrangedSubview(check("Carte graphique RTG : haute résolution d'AGS et du Workbench", { [self] in s.rtg }) { [self] in s.rtg = $0 })
        col.addArrangedSubview(check("Volume SHARED: (Documents/Amiga1200/SHARED)", { [self] in s.shared }) { [self] in s.shared = $0 })
        col.addArrangedSubview(check("NTSC 60 Hz (sinon PAL 50 Hz)", { [self] in s.ntsc }) { [self] in s.ntsc = $0 })
        col.addArrangedSubview(check("Bruit des lecteurs de disquettes", { [self] in s.floppySound }) { [self] in s.floppySound = $0 })
        col.addArrangedSubview(check("Image nette (pixels francs)", { [self] in s.sharp }) { [self] in s.sharp = $0 })

        let power = NSButton(title: "▶  Allumer l'Amiga", target: self, action: #selector(powerOn))
        power.bezelStyle = .rounded; power.controlSize = .large; power.keyEquivalent = "\r"
        power.font = .boldSystemFont(ofSize: 16)
        col.addArrangedSubview(power)
        col.addArrangedSubview(note("Pendant le jeu : cliquez dans la fenêtre pour capturer la souris, ⌥⌘ ou F12 pour la libérer. ⌘ = touches Amiga. Menu Amiga : disquettes, sauvegarde rapide (⌘S / ⌘L), image, plein écran, réinitialisation."))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = col
        col.translatesAutoresizingMaskIntoConstraints = false
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Amiga 1200"
        // Fichiers glissés depuis le Finder : Bibliothèque ou Kickstart
        let drop = DropView(frame: window.contentView?.bounds ?? .zero)
        drop.onDrop = { [self] paths in addFiles(paths) }
        scroll.frame = drop.bounds
        scroll.autoresizingMask = [.width, .height]
        drop.addSubview(scroll)
        window.contentView = drop
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            col.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        let edit = NSMenuItem(); bar.addItem(edit)
        let e = NSMenu(title: "Édition")
        e.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        e.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu = e
        NSApp.mainMenu = bar
    }

    func refresh() {
        let big = Settings.bigBox(s.model)
        var parts = ["Amiga \(s.model.dropFirst())"]
        if big { parts.append(s.jit ? "68040 JIT" : s.model == "A1200" ? "68020" : "68030") }
        if big && s.rtg { parts.append("RTG") }
        parts.append(s.userRom ? "Kickstart \((s.romName as NSString).deletingPathExtension)" : "AROS")
        if !s.hds.isEmpty { parts.append("\(s.hds.count) disque\(s.hds.count > 1 ? "s" : "") dur\(s.hds.count > 1 ? "s" : "")") }
        if !s.df0.isEmpty { parts.append((Settings.isWhd(s.df0) ? "WHDLoad : " : "DF0: ") + (s.df0 as NSString).lastPathComponent) }
        summary.stringValue = parts.joined(separator: " · ")
        romLabel.stringValue = s.userRom ? "✓ \(s.romName)" : "AROS, ROM libre fournie. Pour les jeux, WHDLoad et AGS, choisissez votre Kickstart 3.1."
        df0Label.stringValue = "DF0: " + (s.df0.isEmpty ? "vide" : (s.df0 as NSString).lastPathComponent)
        df1Label.stringValue = "DF1: " + (s.df1.isEmpty ? "vide" : (s.df1 as NSString).lastPathComponent)
        hdLabel.stringValue = s.hds.isEmpty ? "Disques durs : aucun" :
            "Disques durs :\n" + s.hds.enumerated().map { "DH\($0.offset): \(($0.element as NSString).lastPathComponent)" }.joined(separator: "\n")
        modelPopup.selectItem(withTitle: s.model)
        refreshLibrary()
        for (b, get) in checks { b.state = get() ? .on : .off }
    }

    // ---------- éléments ----------
    private var actions: [() -> Void] = []
    func button(_ t: String, _ f: @escaping () -> Void) -> NSButton {
        actions.append(f)
        let b = NSButton(title: t, target: self, action: #selector(run(_:)))
        b.tag = actions.count - 1
        b.bezelStyle = .rounded
        return b
    }
    @objc func run(_ b: NSButton) { actions[b.tag]() }
    func check(_ t: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        actions.append({})
        let b = NSButton(checkboxWithTitle: t, target: self, action: #selector(toggled(_:)))
        b.tag = actions.count - 1
        setters[b.tag] = set
        checks.append((b, get))
        return b
    }
    private var setters: [Int: (Bool) -> Void] = [:]
    @objc func toggled(_ b: NSButton) { setters[b.tag]?(b.state == .on); refresh() }
    func row(_ v: [NSView]) -> NSStackView { let r = NSStackView(views: v); r.orientation = .horizontal; r.spacing = 8; return r }
    func section(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t); l.font = .boldSystemFont(ofSize: 15); return l
    }
    func note(_ t: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: t)
        l.textColor = .secondaryLabelColor; l.font = .systemFont(ofSize: 11)
        l.preferredMaxLayoutWidth = 570
        return l
    }

    // ---------- Bibliothèque ----------
    @objc func libTab() { libKind = [Library.whd, Library.floppy, Library.hdf][max(libTabs.selectedSegment, 0)]; refreshLibrary() }

    func refreshLibrary() {
        let kinds = [Library.whd, Library.floppy, Library.hdf]
        let items = Library.all()
        for (i, k) in kinds.enumerated() {
            let n = items.filter { $0.kind == k }.count
            libTabs.setLabel(["🎮 Jeux WHDLoad", "💾 Disquettes", "🗄 Disques durs"][i] + (n > 0 ? " (\(n))" : ""), forSegment: i)
        }
        libTabs.selectedSegment = kinds.firstIndex(of: libKind) ?? 0
        libList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let shown = items.filter { $0.kind == libKind }
        if shown.isEmpty {
            libList.addArrangedSubview(note(libKind == Library.whd ? "Aucun jeu. Ajoutez des archives WHDLoad (.lha) : un clic les lance, sans disque dur à préparer."
                : libKind == Library.floppy ? "Aucune disquette (ADF, DMS, IPF…)." : "Aucun disque dur (.hdf)."))
            return
        }
        for it in shown {
            var views: [NSView] = []
            let img = NSImageView()
            img.imageScaling = .scaleProportionallyUpOrDown
            img.image = NSImage(contentsOf: Captures.of(it.name))
            img.translatesAutoresizingMaskIntoConstraints = false
            img.widthAnchor.constraint(equalToConstant: 64).isActive = true
            img.heightAnchor.constraint(equalToConstant: 48).isActive = true
            views.append(img)
            let label = NSTextField(labelWithString: it.title + (it.exists ? "" : "  (introuvable)"))
            label.lineBreakMode = .byTruncatingTail
            label.textColor = it.exists ? .labelColor : .tertiaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 300).isActive = true
            views.append(label)
            switch it.kind {
            case Library.whd:
                views.append(ClosureButton("▶ Jouer") { [self] in playWhd(it) })
            case Library.floppy:
                views.append(ClosureButton("▶ Jouer") { [self] in Library.touch(it.path); s.df0 = it.path; refresh(); powerOn() })
                views.append(ClosureButton("DF0:") { [self] in Library.touch(it.path); s.df0 = it.path; refresh() })
            default:
                let on = s.hds.contains(it.path)
                views.append(ClosureButton(on ? "✓ Branché" : "+ Brancher") { [self] in
                    if on { s.hds = s.hds.filter { $0 != it.path } }
                    else if s.hds.count < 8 { Library.touch(it.path); s.hds = s.hds + [it.path] }
                    refresh()
                })
            }
            views.append(ClosureButton("✕") { [self] in Library.remove(it.path); refreshLibrary() })
            libList.addArrangedSubview(row(views))
        }
    }

    /// Fichiers choisis ou glissés : un Kickstart est installé, le reste rangé dans la Bibliothèque
    func addFiles(_ paths: [String]) {
        var added = 0, last: String?
        for p in paths {
            if Library.kind(p) == Library.rom { installRom(p); continue }
            if Library.add(p) { added += 1; last = Library.kind(p) }
        }
        if let k = last { libKind = k }
        if paths.count > 0 && added == 0 && !paths.contains(where: { Library.kind($0) == Library.rom }) {
            alert("Fichiers non reconnus", "La Bibliothèque accepte les jeux WHDLoad (.lha), les disquettes (ADF, DMS, IPF…) et les disques durs (.hdf).")
        }
        refresh()
    }

    func playWhd(_ it: LibItem) {
        guard s.userRom else {
            alert("Kickstart nécessaire", "WHDLoad a besoin d'un vrai Kickstart (3.1 de l'A1200 de préférence) : AROS ne lui suffit pas.")
            return
        }
        Library.touch(it.path)
        launch(it.path)
    }

    @objc func modelChanged() { s.model = modelPopup.titleOfSelectedItem ?? "A1200"; refresh() }

    func pick(_ message: String, multiple: Bool = false) -> String? { pickMany(message, multiple: false).first }
    func pickMany(_ message: String, multiple: Bool) -> [String] {
        let p = NSOpenPanel()
        p.message = message
        p.allowsMultipleSelection = multiple
        p.canChooseDirectories = false
        return p.runModal() == .OK ? p.urls.map(\.path) : []
    }

    func chooseRom() {
        guard let p = pick("Kickstart (fichier ROM, 3.1 pour l'A1200)") else { return }
        installRom(p)
    }

    func installRom(_ p: String) {
        do {
            try? FileManager.default.removeItem(at: Paths.kick)
            try FileManager.default.copyItem(atPath: p, toPath: Paths.kick.path)
            s.rom = "user"; s.romName = (p as NSString).lastPathComponent
        } catch {
            alert("Lecture du Kickstart impossible", error.localizedDescription)
        }
        refresh()
    }

    func addHds() {
        var list = s.hds
        for p in pickMany("Disques durs .hdf (8 au plus)", multiple: true) where !list.contains(p) && list.count < 8 { list.append(p) }
        // Le Workbench d'AGS démarre : placé en premier
        list.sort { a, b in ((a as NSString).lastPathComponent.lowercased() == "workbench.hdf" ? 0 : 1) < ((b as NSString).lastPathComponent.lowercased() == "workbench.hdf" ? 0 : 1) }
        s.hds = list
        refresh()
    }

    func alert(_ t: String, _ msg: String) {
        let a = NSAlert(); a.messageText = t; a.informativeText = msg; a.runModal()
    }

    /// L'émulation dans un nouveau processus de cette application (le cœur ne se rallume pas dans le même)
    @objc func powerOn() {
        if Settings.isWhd(s.df0) && !s.userRom {
            alert("Kickstart nécessaire", "WHDLoad a besoin d'un vrai Kickstart (3.1 de l'A1200 de préférence) : AROS ne lui suffit pas.")
            return
        }
        if !s.df0.isEmpty { Library.add(s.df0) }
        for h in s.hds { Library.add(h) }
        launch(Config.content(s))
        refresh()
    }

    /// L'émulation dans un nouveau processus de cette application
    func launch(_ content: String) {
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--emu", content]
        do { try p.run() } catch { alert("Démarrage impossible", error.localizedDescription) }
    }
}
